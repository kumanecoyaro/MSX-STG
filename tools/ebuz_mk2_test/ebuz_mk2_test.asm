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
; 9. 変形後、5門から中央→内側2門(左右同時)→外側2門(左右同時)の順に
;    間隔を空けて発射(1斉射[4番]とは違い、1発ずつ/ウェーブごとに
;    順次発射。ユーザーが原文で「一斉」と明記していないため)。
; 10. **ここまでで今回の実装は終わり**。以後は本体(開状態)は動かず、
;     連射もしない。oscillation・無限連射・さらなる変形は次回以降の
;     別ステップとして、この土台が確認できてから改めて追加する。
;
; (2026-09-20、実機フィードバック対応: "で変形後は一斉発射じゃねえんだよ
; 指示したように 中央、内2門、外2門と、順次発射だろうが 一斉発射なら
; 一斉って指示してるだろうが" - 上記9番を5門同時発射から中央→内側2門→
; 外側2門の3ウェーブ順次発射へ訂正。同じ発言で報告された「スポーンと
; 同時に画面下当たりに撃ちまくってる」問題は、直前ラウンドで修正した
; 実機専用の割り込み起因の不具合[EBUZ2_TICKの不要なEIによる作業RAM
; 破壊]が実機で完全には解消していなかった可能性、または今回の順次化に
; より1斉発射時の見た目上の「大量の弾が同時に出る」印象が軽減される
; ことで改善する可能性の両方を想定しているが、エミュレータ側では
; 元々この症状を再現できていないため、この訂正で解消するか実機での
; 再確認が必要。)
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
PSG_ADDR EQU 0A0h  ; 無印Ebuz(src/CYBER SHMUP.asm)と同じ標準PSGポート
PSG_DATA EQU 0A1h

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

; (2026-09-20「中央弾はレーザーに変えるんで...レーザーは添付ファイルの
; 16x8のペアで」対応) 添付EbuzIIBeam_16x16.json(fg=7/bg=5)は実際には
; 上半分16x8のみに絵柄があり(下半分16x8は全て0)、これを既存の弾と
; 同じ「左右8x8の2タイル1組」規約で切り出す。専用の新規カラーグループ
; (group10、既存のbody[group8]・bullet[group9]のいずれとも別)を使用。
LASER_L_CODE EQU 80
LASER_R_CODE EQU 81
EBUZ2_LASER_COLOR EQU 075h  ; fg=7(cyan)/bg=5(light blue)

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

; (2026-09-20、"タイミングが悪い 一連のシーケンスEbuzと同じになる
; ように ホールドタイムだな" - リコイル・2度目の発射ウェーブ間隔を
; 無印Ebuz[tools/ebuz_test/ebuz_test.asm]の実際の値に合わせた専用
; ホールド定数。従来はどちらもEBUZ2_ENTRY_STEP_HOLD_TICKS[登場の
; 成長/移動用、4]を流用していたが、無印Ebuzでは局面ごとに全く違う
; 長さを使っている[EBUZ_RECOIL_DURATION=1(反動は一瞬のフリック)、
; EBUZ_FIRE_INTERVAL=2(継続発射の交互間隔)] - この2値をそのまま
; 移植する。) ---
EBUZ2_RECOIL_HOLD_TICKS       EQU 1  ; 無印EbuzのEBUZ_RECOIL_DURATIONと同値
EBUZ2_VOLLEY2_WAVE_HOLD_TICKS EQU 2  ; 無印EbuzのEBUZ_FIRE_INTERVALと同値
; (実機フィードバック対応「レーザーの根元(一番右)が表示されてないな」)
; レーザー発射直後、消去を開始するまでに確実に見せるためのホールド
; tick数(未調整の初期値)。
EBUZ2_LASER_HOLD_TICKS EQU 4

; (2026-09-20 追加訂正「初弾から変形後の2弾目発射までのホールドが
; Ebuzと違ってるだろ 多分1発目発射後0.3か0.5待ってから変形してただろ」
; - 無印Ebuzを再確認したところ、初弾(bullet0)発射直後にその場で10ティック
; 静止ホールドしてから初めて飛び始め、そのまま間を置かず変形(state2)に
; 入る構造だった(EBUZ_WAIT_TICKS呼び出し、B=10)。ユーザーの体感
; 0.3-0.5秒は10ティック[EBUZ_FRAME_WAIT較正値で約0.167秒]よりやや
; 長めの見積もりだが、ソース上の実測値はこの10ティックのみなので、
; ユーザーの目分量ではなくこの実値をそのまま移植する。従来のMk2は
; 一斉発射(volley1)直後に間を置かず即座にリコイルへ入っていたため、
; この「発射後の静止ホールド」区間自体が丸ごと欠落していた。
; さらに続けて「もっと長く15Tick待つように」との追加指示を受け10→15へ
; 変更[無印Ebuz実測値からの意図的な乖離、ユーザー体感を優先]。) ---
EBUZ2_VOLLEY1_HOLD_TICKS EQU 15  ; 「もっと長く15Tick待つように」指示で10→15

; (2026-09-20 追加訂正「変形後弾を撃つ前のホールドを５Tick挿入」 -
; 変形(state2)描画完了[EBUZ2_TRANSFORM_DONE]から2度目の発射(中央弾)
; までの間に、専用のホールドを新設して挿入する。既存のEBUZ2_ENTRY_
; HOLD[変形描画自体のペーシングに使っている4tick、登場フェーズと共用]
; とは別に、この「変形後・発射前」区間専用の値として独立させる。) ---
EBUZ2_VOLLEY2_PRE_FIRE_HOLD_TICKS EQU 5

; (2026-09-20追加訂正「変形時に1セルズレてるんで上に1セル上げてくれ
; 変形前は高さ5セルで変形後7セルなんでセンターがズレてるんで」 -
; 閉状態(5行、row_top=9〜13)の中心行はrow_top+2=11。開状態(7行)を
; 従来通りrow_top(9)〜+6(15)で描くと中心行はrow_top+3=12になり、
; 閉→開の変形前後で中心が1行下にズレる。開状態側の描画開始行を
; EBUZ2_ENTRY_TARGET_ROW_TOP-1(=8)へ引き上げ、rowを8〜14にすることで
; 中心行を8+3=11に揃え、閉状態の中心(11)と一致させた。) ---
EBUZ2_S2_ROW_TOP EQU EBUZ2_ENTRY_TARGET_ROW_TOP-1  ; 開状態(7行)の描画開始行(=8)

; --- Ebuz Mk2-2(開状態、7行、添付Ebuzmkii2_64x64_2.jsonを実際に
; Pythonで解析して確認済み)の発射管定数。5門(外側上/内側上/中央/
; 内側下/外側下)はrow_top=EBUZ2_S2_ROW_TOP(8)固定(変形後は
; 二度と動かない)。行ベースアドレスはrow8=1900h,9=1920h,11=1960h,
; 13=19A0h,14=19C0h。
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
EBUZ2_ROW_OT_BASE  EQU 1900h  ; row8  (開状態local row0、外側上)
EBUZ2_ROW_IT_BASE  EQU 1920h  ; row9  (開状態local row1、内側上)
EBUZ2_ROW_S2C_BASE EQU 1960h  ; row11 (開状態local row3、中央)
EBUZ2_ROW_IB_BASE  EQU 19A0h  ; row13 (開状態local row5、内側下)
EBUZ2_ROW_OB_BASE  EQU 19C0h  ; row14 (開状態local row6、外側下)
; (実機フィードバック対応「レーザーも弾も発射位置が遠い ちゃんと
; 本体先端から出るように右に修正」) 開状態ボディは行ごとに先端の列が
; 異なる形状(中央行が最も左へ突き出るV字型、実測: 中央=col23・
; 内側(IT/IB)=col24・外側(OT/OB)=col25)。従来は全門共通の1列
; (col21)で発射していたため、中央は隙間ゼロで正しかったが内側は
; 1列・外側は2列の隙間が空いて見えていた。門ごとに「発射位置R側の列
; +1 = その門の先端列」となる専用の列を用意し、隙間を全門ゼロに揃える。
EBUZ2_S2_FIRE_COL  EQU 21      ; 中央(レーザー、先端col23) - 変更なし
EBUZ2_S2_FIRE_COL_INNER EQU 22 ; 内側IT/IB(先端col24)
EBUZ2_S2_FIRE_COL_OUTER EQU 23 ; 外側OT/OB(先端col25)

; 上下移動のペーシング。(2026-09-20追加指示「一応シーケンス指示
; しとく...変形後の交互発射を開始したら 画面2行目から下は5行目までを
; 往復だぞ」により、往復範囲をrow2〜row5(リテラル指定)に変更。
; さらに「開始したら」の通り、この往復はEBUZ2_S2_ROW_TOP(8)での
; 変形直後(=中央から1発〜内側2門〜外側2門の順次発射までの間)は
; 起動せず、無制限交互発射(EBUZ2_VOLLEY2_ALT_LOOP)が始まる瞬間に
; 本体を往復の起点へ動かして初めて往復を開始する(EBUZ2_VOLLEY2_ALT_
; LOOP直前の起動処理を参照)。EBUZ2_S2_MOVE_INTERVAL_TICKSごとに1行
; だけ動く(未調整の初期値)。
; (2026-09-20追加訂正「移動範囲が狭い 下は3セル 上は4セル広く」により
; 再拡張。下方向(MAX_ROW、row5→8)は要求通り+3、上方向(MIN_ROW、
; row2→-2の要求)はガード帯(row0固定・本体7行のためROW_CURは1が
; 下限)により+4のうち+1(row2→1)しか実現できない - この制約はユーザー
; へ別途報告済み。)
; (2026-09-20さらに追加訂正「そうじゃねえよ 上はこれでいいがYはRow20
; までの範囲で」を受けMAX_ROW=13(ガード帯row20-23の物理限界値、
; 本体7行のため13+6=19が最後の非ガード行)へ変更。一度13→12へ
; 修正したが、これはユーザー側の目視ミスによる指摘だったと判明
; ("移動範囲はRow13のままでいい こちらの目視でのミス")し、13へ
; 差し戻し。
; 上方向(MIN_ROW=1)は変更なし - row0はガード帯そのもの(常にcode=16
; 固定)であり、本体7行のためROW_CURを0にすると本体が row0-6 に
; 掛かりガード帯を確実に破壊する。MIN_ROWを0にすることは物理的に
; 不可能なため、ここは1のまま維持する。)
; (2026-09-20さらに訂正「一周なんだから中央まで戻ったら停止だろうが
; よ」: 「1往復」の停止位置をMIN_ROW到達時点からEBUZ2_S2_ROW_TOP
; (=中央、8)到達時点へ変更 - 中央から下方向へ出発しMAX_ROWで折り
; 返した後、出発点の中央に戻ってきたところで停止するのが「一周」の
; 正しい意味だと考えたが、これも誤りだった。
; (2026-09-20さらに訂正「お前は一周の意味もわからんのか 下に動いて
; Row13まで行き Row0まで到達してまた中央に来たら停止して発射だろうが」
; : 正しい「一周」は中央から出発→下端(MAX_ROW=13)→上端(MIN_ROW、
; ユーザーの言う「Row0」はガード帯そのものであり物理的に到達不可能
; なため、既に確認済みの物理限界であるMIN_ROW=1をそのまま「上端」と
; して扱う)→出発点の中央、の順に両端を1回ずつ経由してから中央に
; 戻ってきたところで停止。上方向移動はMAX_ROW到達後、MIN_ROWで折り
; 返して下方向へ戻り、REACHED_MIN=1かつ中央到達で初めて一周完了と
; する(EBUZ2_UPDATE_S2_MOVE参照)。) ---
EBUZ2_S2_MOVE_INTERVAL_TICKS EQU 4
EBUZ2_S2_MOVE_MIN_ROW EQU 1
EBUZ2_S2_MOVE_MAX_ROW EQU 13

; ============================================================================
; RAMワークエリア。
;
; (2026-09-20、実機フィードバック対応: "何故かスポーン時に画面下部に
; 弾撃ちまくるコード入れてんだろうが" - openMSXのwatchpointで実測して
; 特定した真因) 当初は無印Ebuzと同じ0F300h付近を再利用していたが、
; CALL INIT32(BIOS内部でEI+HALTのvblank待ちを行う)を境に本ファイルは
; 以後ずっと割り込み許可状態のままになる(WRTVRM/LDIRVM等のBIOSコール
; 自体が内部でEIし直すため、呼び出し側でDIし直しても次のBIOSコールで
; また割り込みが有効に戻ってしまうと実測で確認済み - このファイルは
; 弾の描画そのものがWRTVRM経由のため、割り込みを本当の意味で止め
; 続けることは事実上不可能と判断)。この状態でBIOSの標準割り込み
; ハンドラ(H.TIMIフックの手前で毎垂直帰線ごとに走るキー走査・JIFFY
; 更新等のBIOS自身のシステム変数書き込み)が実際に使うRAM範囲を
; openMSXのwatchpointで直接計測した結果、少なくとも0F352h-0F3F6h・
; 0FBD9h-0FBEFh・0FC9Eh-0FC9Fhが実測で書き換えられることを確認した
; (このファイル自身の0F300h-0F35Fh使用がまさにこの範囲と衝突して
; いた - これが「本体の位置と無関係な場所に弾が出現し続ける」報告の
; 直接原因)。実測で一切書き込みが観測されなかった0F100h台へ全面移設し
; 解消(STACKTOP=0F380hからも0FBD9h危険域からも大きく離れており、
; どちらの安全マージンも十分)。
; ============================================================================
EBUZ2_BODY_ROW     EQU 0F100h  ; 1 byte: 本体の現在のlocal row0のnt行
                                ; (登場の移動フェーズでのみ使用、発射後は不変)
EBUZ2_NEXT_0       EQU 0F101h  ; 1 byte: local row0プールのローテーションカウンタ
EBUZ2_NEXT_1       EQU 0F102h  ; 1 byte: local row1の同上
EBUZ2_NEXT_2       EQU 0F103h  ; 1 byte: local row2(中央)の同上
EBUZ2_NEXT_3       EQU 0F104h  ; 1 byte: local row3の同上
EBUZ2_NEXT_4       EQU 0F105h  ; 1 byte: local row4の同上
; EBUZ2_UPDATE_SLOT(共有プール更新ルーチン)が参照する「今どの行を
; 対象にしているか」のスクラッチ(呼び出し元がCALL直前にセットする、
; 無印EbuzのEBUZ_CUR_ROW_BASEと全く同じ役割)。
EBUZ2_CUR_ROW_BASE EQU 0F106h  ; 2 bytes

; 開状態(Mk2-2)5門分のローテーションカウンタ(0F108h-0F10Ch、
; 0F107hは未使用の1byteパディング)。
EBUZ2_S2_OT_NEXT EQU 0F108h
EBUZ2_S2_IT_NEXT EQU 0F109h
EBUZ2_S2_C_NEXT  EQU 0F10Ah
EBUZ2_S2_IB_NEXT EQU 0F10Bh
EBUZ2_S2_OB_NEXT EQU 0F10Ch

; (2026-09-20追加指示「上下移動を追加 発射位置のみ追従な ワインダー
; じゃないからな」 - 変形後の本体を上下にゆっくり移動させるが、既に
; 発射済みの弾は追従させず直進を続けさせる(ホーミングではない)。
; このため開状態5門は「プール全体で1つの固定行を共有」する従来方式
; (EBUZ2_CUR_ROW_BASE)のままでは実装できない - 本体が移動すると
; 全弾が一斉に新しい行へ引きずられてしまう。1発ごとに発射した瞬間の
; 行番号を記録する専用ROWS配列(EBUZ2_S2_*_ROWS)を新設し、以後は
; その弾専用の固定行として扱う。ROWS配列はCOLS配列の直後(+8)に
; 配置し、EBUZ2_UPDATE_SLOT_ROWED(後方で定義)がCOLSスロットの
; アドレス+8で対応するROWSスロットを直接参照できるようにした。) ---
EBUZ2_S2_ROW_CUR    EQU 0F10Dh  ; 1 byte: 開状態本体の現在の描画開始行
EBUZ2_S2_MOVE_ACTIVE EQU 0F10Eh ; 1 byte: 0=まだ移動しない(変形前)/1=移動中
EBUZ2_S2_MOVE_DIR   EQU 0F10Fh  ; 1 byte: 0=下へ移動中/1=上へ移動中

; 各プール8スロット×1byte(列番号のみ、無印EbuzのEBUZ_TOP_COLS等と
; 全く同じ設計 - 行はプールごとにEBUZ2_ROW_*_BASEで固定)。
; EBUZ2_SLOT_EMPTY(255)で非活性。
EBUZ2_COLS_0 EQU 0F110h  ; local row0、8 bytes
EBUZ2_COLS_1 EQU 0F118h  ; local row1、8 bytes
EBUZ2_COLS_2 EQU 0F120h  ; local row2(中央)、8 bytes
EBUZ2_COLS_3 EQU 0F128h  ; local row3、8 bytes
EBUZ2_COLS_4 EQU 0F130h  ; local row4、8 bytes(0F137hで終了)

; 開状態(Mk2-2)5門分の列プール(0F138h以降、閉状態プールの直後)。
; COLSの直後(+8)に同じ8スロット構成のROWS(発射時の行番号)を配置 -
; EBUZ2_UPDATE_SLOT_ROWEDがCOLSアドレス+8でROWSを直接参照するため、
; この「COLS→ROWS」ペアの並びと+8オフセットは変更しないこと。
EBUZ2_S2_OT_COLS EQU 0F138h  ; 外側上、8 bytes
EBUZ2_S2_OT_ROWS EQU 0F140h  ; 外側上の発射時行番号、8 bytes
EBUZ2_S2_IT_COLS EQU 0F148h  ; 内側上、8 bytes
EBUZ2_S2_IT_ROWS EQU 0F150h  ; 内側上の発射時行番号、8 bytes
EBUZ2_S2_C_COLS  EQU 0F158h  ; 中央、8 bytes
EBUZ2_S2_C_ROWS  EQU 0F160h  ; 中央の発射時行番号、8 bytes
EBUZ2_S2_IB_COLS EQU 0F168h  ; 内側下、8 bytes
EBUZ2_S2_IB_ROWS EQU 0F170h  ; 内側下の発射時行番号、8 bytes
EBUZ2_S2_OB_COLS EQU 0F178h  ; 外側下、8 bytes
EBUZ2_S2_OB_ROWS EQU 0F180h  ; 外側下の発射時行番号、8 bytes(0F187hで
                               ; 終了、引き続き実測で安全と確認済みの
                               ; 0F100h台に収まる)
EBUZ2_S2_MOVE_COUNTDOWN EQU 0F188h  ; 1 byte: 次の1行移動までの残りtick数
EBUZ2_ROWED_TMP_ADDR EQU 0F189h  ; 2 bytes: EBUZ2_UPDATE_SLOT_ROWEDの
                                  ; 作業用スクラッチ(行ベースアドレス
                                  ; の一時退避、CALL跨ぎでAFが壊れる
                                  ; ためHL計算結果をここに逃がす)
; (2026-09-20「では一往復したら上下動停止して 交互連射も停止」対応、
; 続けて「一周」の正しい意味を2回に渡り訂正: 最終的に「下に動いて
; Row13まで行き Row0まで到達してまた中央に来たら停止して発射」=
; 中央→下端(MAX_ROW)→上端(MIN_ROW)→中央、の順に両端を1回ずつ経由
; してから出発点(中央)に戻ってきて初めて「一周」完了。)
; REACHED_MAX: 0=まだ下端(MAX_ROW)未到達/1=到達済み。
; REACHED_MIN: 0=まだ上端(MIN_ROW)未到達/1=到達済み(下端到達後に
; しか立たない)。下方向移動中にREACHED_MIN=1かつ中央(ROW_TOP)へ
; 到達したら、そこが「一周」完了地点。
EBUZ2_S2_MOVE_REACHED_MAX EQU 0F18Bh  ; 1 byte
EBUZ2_S2_MOVE_ROUNDTRIP_DONE EQU 0F18Ch  ; 1 byte: 1=1周完了・上下動/
                                          ; 交互連射とも停止済み
EBUZ2_S2_MOVE_REACHED_MIN EQU 0F18Dh  ; 1 byte

; (2026-09-20「では中央発射のリコイル追加 発射音追加 Ebuzと同じで
; いい」対応) 発射音は無印Ebuz(src/CYBER SHMUP.asm)のSOUND_EBUZ_FIRE
; (channel Aのノイズジェネレータ、周期14、SND_TIMER=15から毎tick-1の
; 直線減衰、TICK AND 1によるデューティゲート)と全く同じ構造を
; このテストROM専用に移植する。このファイルには元々PSG関連のコードが
; 一切無かったため、最小限のTICKカウンタ・SND_TIMER・R8書き込みを
; 新設する。
EBUZ2_TICK_COUNTER EQU 0F18Eh  ; 1 byte: デューティゲート用の毎tick+1カウンタ
EBUZ2_SND_TIMER     EQU 0F18Fh  ; 1 byte: 発射音の残りenvelopeレベル(0=無音)

; (2026-09-20「中央弾はレーザーに変えるんで...繋がった状態で左端まで
; 到達して その後右から順に消すように」対応) 中央から発射する弾を、
; 発射時点で列0〜21(FIRE_COL)を一括して繋げて埋める「レーザー」へ
; 変更。列2つ(L+R)を1ユニットとして0-1,2-3,...,20-21の計11ユニット、
; 発射時に一括描画し、以後1tickに1ユニットずつ右側(発射位置側、col
; 20-21)から順に消していく。
EBUZ2_LASER_ACT EQU 0F190h  ; 1 byte: 0=非活性/1=消去シーケンス進行中
EBUZ2_LASER_ROW EQU 0F191h  ; 1 byte: 発射時に固定した描画行(ROW_CUR+3)
EBUZ2_LASER_RETRACT_UNIT EQU 0F192h  ; 1 byte: 次に消すユニット番号(10→0)
; (実機フィードバック対応「レーザーの根元(一番右)が表示されてないな」)
; 発射直後、リコイル演出の最初の1tickホールドがEBUZ2_TICK経由で
; EBUZ2_UPDATE_S2_LASERも同時に1tick分進めてしまい、根元(発射位置側の
; ユニット)が完全に描画された状態のまま1tickも表示されずに消去され
; 始めていた。発射直後の数tickは消去を始めず、繋がった全体像を確実に
; 見せてから消去に入るようにするためのホールドカウンタ。
EBUZ2_LASER_HOLD_COUNTDOWN EQU 0F193h  ; 1 byte: 消去開始までの残りtick数

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

; 上下移動の消去用(開状態7行、col23-28の6byte - リコイル用に拡張
; 済みの4行[OT/IT/IB/OB]がその時点でどちらの位置[REST/RECOIL]に
; あっても確実に消せるよう、全7行ともcol28まで6byte消去する)。
EBUZ2_BLANK6:
    DB 0,0,0,0,0,0

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

; (2026-09-20追加指示「リコイル動作を追加」 - 無制限交互発射の各発射
; ごとに、無印Ebuzの継続発射リコイル(EBUZ_ROW_0ABC_REST/RECOIL、
; "打つときは反動を見せたいんで 上下の3セル分を1セル右に 打ったら
; 元位置に戻せ")と同じ考え方を、発射したペアの行(外側=OT/OB、
; 内側=IT/IB)だけに適用する。EBUZ2_ROW_S2_0/S2_6[外側]・S2_1/S2_5
; [内側]はいずれも元は5byte(col23-27)だが、リコイル時に1セル右へ
; ずらすための予備セル(col28)を確保するため、この4行だけ6byte
; (col23-28)のREST/RECOIL版を新設する(通常時の描画[EBUZ2_ROW_S2_0
; 等の5byte版]自体は無変更 - col28は初期状態でVRAM既定の0のままな
; ため、そのままREST相当として扱える)。外側上(S2_0)と外側下(S2_6)、
; 内側上(S2_1)と内側下(S2_5)はそれぞれ中身が同一のため、1組ずつの
; REST/RECOILペアを両方の行で使い回す。
EBUZ2_ROW_S2_OUTER_REST:
    DB 0,0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,0
EBUZ2_ROW_S2_OUTER_RECOIL:
    DB 0,0,0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C
EBUZ2_ROW_S2_INNER_REST:
    DB 0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_C,0
EBUZ2_ROW_S2_INNER_RECOIL:
    DB 0,0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_C

; (2026-09-20「では中央発射のリコイル追加」対応) 中央(EBUZ2_ROW_S2_3)
; は元々5byteとも全て埋まっている(A,B,C,D,D、leading 0が無い)ため、
; OUTER/INNERと同じ「6byte化してcol28を予備セルに」方式で1セル右へ
; シフトする。REST=通常位置+末尾に空セルを1つ追加しただけ、RECOIL=
; 中身を丸ごと1セル右へずらし先頭(col23)を空にしたもの。
EBUZ2_ROW_S2_CENTER_REST:
    DB EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_D,EBUZ2_CODE_D,0
EBUZ2_ROW_S2_CENTER_RECOIL:
    DB 0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_D,EBUZ2_CODE_D

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

; 開状態(Mk2-2)5門専用のスロット更新(2026-09-20「上下移動を追加
; 発射位置のみ追従な」対応)。EBUZ2_UPDATE_SLOTとの違いは、行を
; 呼び出し元が指定する共有EBUZ2_CUR_ROW_BASEからではなく、この
; スロット専用の行番号(HL+8、RAMレイアウトの「COLS→ROWS」+8規約
; 参照)から毎回読み直す点のみ - これにより本体が上下移動しても、
; 既に発射済みの弾は発射時の行に固定されたまま動かない(本体の
; 現在位置に追従するのは次に発射される弾だけ)。IN: HL=スロットの
; 列番号バイトのアドレス(COLS配列内)。
EBUZ2_UPDATE_SLOT_ROWED:
    LD A,(HL)
    CP EBUZ2_SLOT_EMPTY
    RET Z
    PUSH HL
    PUSH AF
    LD DE,8 : ADD HL,DE
    LD B,(HL)
    LD C,0
    CALL EBUZ2_CALC_ADDR
    LD (EBUZ2_ROWED_TMP_ADDR),HL
    POP AF
    PUSH AF
    LD E,A : LD D,0
    LD HL,(EBUZ2_ROWED_TMP_ADDR)
    ADD HL,DE
    LD B,0 : LD C,0
    CALL EBUZ2_WRITE2
    POP AF
    OR A
    JR Z,EBUZ2_USR_OFF
    DEC A
    POP HL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,(EBUZ2_ROWED_TMP_ADDR)
    ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET
EBUZ2_USR_OFF:
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
; 2026-09-20「上下移動を追加 発射位置のみ追従な」対応により、共有の
; EBUZ2_CUR_ROW_BASEセットは不要になった(EBUZ2_UPDATE_SLOT_ROWEDが
; スロットごとに記録済みの行番号を直接読むため) - 各プールとも
; 8スロット分をそのままROWED版へ渡すだけの単純なループに変わった。
; ============================================================================
EBUZ2_UPDATE_POOL_OT:
    LD HL,EBUZ2_S2_OT_COLS+0 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_OT_COLS+1 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_OT_COLS+2 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_OT_COLS+3 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_OT_COLS+4 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_OT_COLS+5 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_OT_COLS+6 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_OT_COLS+7 : CALL EBUZ2_UPDATE_SLOT_ROWED
    RET

EBUZ2_UPDATE_POOL_IT:
    LD HL,EBUZ2_S2_IT_COLS+0 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_IT_COLS+1 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_IT_COLS+2 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_IT_COLS+3 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_IT_COLS+4 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_IT_COLS+5 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_IT_COLS+6 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_IT_COLS+7 : CALL EBUZ2_UPDATE_SLOT_ROWED
    RET

EBUZ2_UPDATE_POOL_S2C:
    LD HL,EBUZ2_S2_C_COLS+0 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_C_COLS+1 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_C_COLS+2 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_C_COLS+3 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_C_COLS+4 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_C_COLS+5 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_C_COLS+6 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_C_COLS+7 : CALL EBUZ2_UPDATE_SLOT_ROWED
    RET

EBUZ2_UPDATE_POOL_IB:
    LD HL,EBUZ2_S2_IB_COLS+0 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_IB_COLS+1 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_IB_COLS+2 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_IB_COLS+3 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_IB_COLS+4 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_IB_COLS+5 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_IB_COLS+6 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_IB_COLS+7 : CALL EBUZ2_UPDATE_SLOT_ROWED
    RET

EBUZ2_UPDATE_POOL_OB:
    LD HL,EBUZ2_S2_OB_COLS+0 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_OB_COLS+1 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_OB_COLS+2 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_OB_COLS+3 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_OB_COLS+4 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_OB_COLS+5 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_OB_COLS+6 : CALL EBUZ2_UPDATE_SLOT_ROWED
    LD HL,EBUZ2_S2_OB_COLS+7 : CALL EBUZ2_UPDATE_SLOT_ROWED
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
; (2026-09-20「上下移動を追加 発射位置のみ追従な ワインダーじゃない
; からな」対応): 5門とも、コンパイル時定数だったEBUZ2_ROW_*_BASEの
; 代わりに、発射する瞬間のEBUZ2_S2_ROW_CUR(+各門固有の行オフセット
; 0/1/3/5/6、変形描画データのlocal row0-6に対応)を読んで発射行を
; 決定するよう変更。この行番号は同時にスロット専用のROWS配列
; (COLS+8)へ記録し、以後この弾自身の固定行として使う(本体が後で
; 移動しても、既に発射済みのこの弾は追従しない)。EBUZ2_ROW_OT/IT/
; S2C/IB/OB_BASE定数自体は変形直後の初期描画にのみ引き続き使用。
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
    LD A,EBUZ2_S2_FIRE_COL_OUTER
    LD (HL),A
    PUSH HL
    LD DE,8 : ADD HL,DE
    LD A,(EBUZ2_S2_ROW_CUR)
    LD (HL),A
    POP HL
    LD B,A : LD C,EBUZ2_S2_FIRE_COL_OUTER
    CALL EBUZ2_CALC_ADDR
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
    LD A,EBUZ2_S2_FIRE_COL_INNER
    LD (HL),A
    PUSH HL
    LD DE,8 : ADD HL,DE
    LD A,(EBUZ2_S2_ROW_CUR)
    ADD A,1
    LD (HL),A
    POP HL
    LD B,A : LD C,EBUZ2_S2_FIRE_COL_INNER
    CALL EBUZ2_CALC_ADDR
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET

; (2026-09-20「中央弾はレーザーに変えるんで」対応によりEBUZ2_FIRE_
; S2C_BULLET[通常弾方式の中央発射]は不要になったため削除。以後の
; 中央発射はEBUZ2_FIRE_S2_LASERのみ[EBUZ2_S2_STOP_SEQUENCE参照])。

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
    LD A,EBUZ2_S2_FIRE_COL_INNER
    LD (HL),A
    PUSH HL
    LD DE,8 : ADD HL,DE
    LD A,(EBUZ2_S2_ROW_CUR)
    ADD A,5
    LD (HL),A
    POP HL
    LD B,A : LD C,EBUZ2_S2_FIRE_COL_INNER
    CALL EBUZ2_CALC_ADDR
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
    LD A,EBUZ2_S2_FIRE_COL_OUTER
    LD (HL),A
    PUSH HL
    LD DE,8 : ADD HL,DE
    LD A,(EBUZ2_S2_ROW_CUR)
    ADD A,6
    LD (HL),A
    POP HL
    LD B,A : LD C,EBUZ2_S2_FIRE_COL_OUTER
    CALL EBUZ2_CALC_ADDR
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
; 本体形状の汎用描画/消去(Ebuz Mk2-2開状態、7行)。Input: A=row_top
; (local row0の目標nt行)。EBUZ2_ROW_S2_0-6を7行分、row_top〜row_top+6へ
; 順にLDIRVMする(2026-09-20「上下移動を追加」対応の新設 - 従来は
; 変形時に一度だけ描く専用のインライン展開だったが、上下移動の
; 毎ステップでも同じ描画が必要になったため、EBUZ2_DRAW_BODY_AT/
; ERASE_BODY_AT[閉状態5行版]と同じ「A=row_topを取るサブルーチン」
; 形式へ切り出した)。消去は列23-28の6byte(EBUZ2_BLANK6)を使う -
; リコイル用に列28まで拡張済みの4行[OT/IT/IB/OB]がどちらの状態
; [REST/RECOIL]で消去されても確実に空にするため。
; ============================================================================
EBUZ2_DRAW_S2_BODY_AT:
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

EBUZ2_ERASE_S2_BODY_AT:
    PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK6 : POP DE : LD BC,6 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK6 : POP DE : LD BC,6 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK6 : POP DE : LD BC,6 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK6 : POP DE : LD BC,6 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK6 : POP DE : LD BC,6 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK6 : POP DE : LD BC,6 : CALL LDIRVM
    POP AF : INC A
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK6 : POP DE : LD BC,6 : CALL LDIRVM
    RET

; 上下移動(2026-09-20「では上下移動を追加 発射位置のみ追従な
; ワインダーじゃないからな」対応)。EBUZ2_S2_MOVE_ACTIVE=1の間、
; EBUZ2_TICKから毎ティック呼ばれる。EBUZ2_S2_MOVE_INTERVAL_TICKSに
; 1回、本体をEBUZ2_S2_MOVE_MIN_ROW〜MAX_ROWの範囲で1行ずつ上下に
; 往復させる。弾自体の追従は行わない(EBUZ2_FIRE_*_BULLET/
; EBUZ2_UPDATE_SLOT_ROWED側の設計で自動的に「発射時点の行に固定」
; されるため、ここでは本体の描画位置を動かすだけでよい)。
EBUZ2_UPDATE_S2_MOVE:
    LD A,(EBUZ2_S2_MOVE_ACTIVE)
    OR A
    RET Z
    LD A,(EBUZ2_S2_MOVE_COUNTDOWN)
    DEC A
    LD (EBUZ2_S2_MOVE_COUNTDOWN),A
    RET NZ
    LD A,EBUZ2_S2_MOVE_INTERVAL_TICKS
    LD (EBUZ2_S2_MOVE_COUNTDOWN),A
    LD A,(EBUZ2_S2_ROW_CUR)
    CALL EBUZ2_ERASE_S2_BODY_AT
    LD A,(EBUZ2_S2_MOVE_DIR)
    OR A
    JR Z,EBUZ2_USM_DOWN
    ; ---- 上方向移動中(下端MAX_ROWへ到達した後、折り返して上端へ
    ; 向かっている段階) ----
    LD A,(EBUZ2_S2_ROW_CUR)
    DEC A
    LD (EBUZ2_S2_ROW_CUR),A
    CP EBUZ2_S2_MOVE_MIN_ROW
    JR NZ,EBUZ2_USM_DRAW
    ; 上端(MIN_ROW)到達: フラグを立てて下方向へ折り返す(まだ停止
    ; しない、中央に戻るまで継続)。
    LD A,1
    LD (EBUZ2_S2_MOVE_REACHED_MIN),A
    XOR A
    LD (EBUZ2_S2_MOVE_DIR),A
    JR EBUZ2_USM_DRAW
EBUZ2_USM_DOWN:
    LD A,(EBUZ2_S2_ROW_CUR)
    INC A
    LD (EBUZ2_S2_ROW_CUR),A
    LD B,A  ; 新しい行番号を退避(このブロック内はCALLを挟まないので安全)
    ; 既に上端(MIN_ROW)を経由済み(REACHED_MIN=1)で、かつ出発点の
    ; 中央(ROW_TOP)まで戻ってきたなら「一周」完了。往路(中央→下端へ
    ; 向かう最初の下降)ではREACHED_MINはまだ0なので誤検知しない。
    LD A,(EBUZ2_S2_MOVE_REACHED_MIN)
    OR A
    JR Z,EBUZ2_USM_DOWN_MAXCHECK
    LD A,B
    CP EBUZ2_S2_ROW_TOP
    JR NZ,EBUZ2_USM_DRAW
    LD A,1
    LD (EBUZ2_S2_MOVE_ROUNDTRIP_DONE),A
    XOR A
    LD (EBUZ2_S2_MOVE_ACTIVE),A
    JR EBUZ2_USM_DRAW
EBUZ2_USM_DOWN_MAXCHECK:
    LD A,B
    CP EBUZ2_S2_MOVE_MAX_ROW
    JR NZ,EBUZ2_USM_DRAW
    LD A,1
    LD (EBUZ2_S2_MOVE_DIR),A
    LD (EBUZ2_S2_MOVE_REACHED_MAX),A  ; A=1のまま流用
EBUZ2_USM_DRAW:
    LD A,(EBUZ2_S2_ROW_CUR)
    CALL EBUZ2_DRAW_S2_BODY_AT
    RET

; リコイル演出の直後、本来は無条件にEBUZ2_S2_MOVE_ACTIVEを1へ戻して
; いたが、その間に1往復が完了(EBUZ2_S2_MOVE_ROUNDTRIP_DONE=1)して
; いた場合はここで誤って上下動を再起動させないよう、必ずこの
; ルーチン経由で復帰させる。
EBUZ2_S2_RESTORE_MOVE_ACTIVE:
    LD A,(EBUZ2_S2_MOVE_ROUNDTRIP_DONE)
    OR A
    RET NZ
    LD A,1
    LD (EBUZ2_S2_MOVE_ACTIVE),A
    RET

; (2026-09-20「では中央発射のリコイル追加 発射音追加 Ebuzと同じで
; いい」対応) 発射音: 無印Ebuz(src/CYBER SHMUP.asm)のSOUND_EBUZ_FIRE
; と全く同じ構造(channel Aのノイズ周期=14、SND_TIMER=15からの直線
; 減衰、TICK最下位ビットによる1:1デューティゲート)をこのファイル専用に
; 移植。
EBUZ2_SOUND_FIRE:
    DI
    LD A,6 : OUT (PSG_ADDR),A
    LD A,14 : OUT (PSG_DATA),A
    EI
    LD A,15
    LD (EBUZ2_SND_TIMER),A
    RET

; 毎tickEBUZ2_TICKから呼ぶ: デューティゲート用カウンタを進め、R8
; (channel A音量)へその時点の値を書き込み、SND_TIMERを1減衰させる。
; 無印EbuzのCALC_NOISE_GATE_VOLUME+SOUND_UPDATE(ノイズ分岐のみ)と
; 同じ考え方。
EBUZ2_SOUND_UPDATE:
    LD A,(EBUZ2_TICK_COUNTER)
    INC A
    LD (EBUZ2_TICK_COUNTER),A
    AND 1
    JR NZ,EBUZ2_SU_SILENT
    LD A,(EBUZ2_SND_TIMER)
    JR EBUZ2_SU_WRITE
EBUZ2_SU_SILENT:
    XOR A
EBUZ2_SU_WRITE:
    LD B,A
    DI
    LD A,8 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A
    EI
    LD A,(EBUZ2_SND_TIMER)
    OR A
    RET Z
    DEC A
    LD (EBUZ2_SND_TIMER),A
    RET

; (2026-09-20「中央弾はレーザーに変えるんで レーザーは添付ファイルの
; 16x8のペアで レーザーだから弾と違って繋がった状態で左端まで到達して
; その後右から順に消すように」対応、続けて実機フィードバック対応
; 「レーザーも弾も発射位置が遠い ちゃんと本体先端から出るように右に
; 修正」) 発射時に列1-22を一括描画する(弾のように1tickずつ移動する
; のではなく、瞬時に繋がった状態で左端に到達済みとして描く)。列は
; 元々0-21だったが、2列1組のタイリングを列0起点にすると右端が必ず
; 奇数列(21)止まりになり、中央の本体先端(col23)に隣接する偶数列
; (col22)まで届かず1列の隙間が空いていた実バグを修正、タイリングの
; 起点を列1へ1列シフトして右端をcol22(先端col23と隙間ゼロで隣接)に
; 揃えた(左端は列0ではなく列1までになるが、画面左端まであと1列という
; 誤差はほぼ視認できない程度と判断)。IN: 呼び出し元はEBUZ2_S2_ROW_CUR
; が確定済みの状態で呼ぶこと(中央の発射行=ROW_CUR+3を内部で計算する)。
EBUZ2_FIRE_S2_LASER:
    LD A,(EBUZ2_S2_ROW_CUR)
    ADD A,3
    LD (EBUZ2_LASER_ROW),A
    LD B,A
    LD C,1
EBUZ2_FLS_LOOP:
    CALL EBUZ2_CALC_ADDR
    PUSH BC
    LD B,LASER_L_CODE : LD C,LASER_R_CODE : CALL EBUZ2_WRITE2
    POP BC
    LD A,C : ADD A,2 : LD C,A
    CP 23
    JR NZ,EBUZ2_FLS_LOOP
    LD A,10
    LD (EBUZ2_LASER_RETRACT_UNIT),A
    LD A,EBUZ2_LASER_HOLD_TICKS
    LD (EBUZ2_LASER_HOLD_COUNTDOWN),A
    LD A,1
    LD (EBUZ2_LASER_ACT),A
    RET

; 毎tickEBUZ2_TICKから呼ぶ: EBUZ2_LASER_ACT=1の間、まずEBUZ2_LASER_
; HOLD_COUNTDOWNが尽きるまでは何もせず待ち(発射直後のリコイル演出用
; 1tickホールドと消去処理が同一tickで重なり、繋がった全体像[根元含む]
; が1tickも表示されないまま消え始めていた実バグの修正)、尽きてから
; 発射位置側(列21-22)から順に1ユニット(2列)ずつ消していき、列1-2を
; 消したら非活性化する。
EBUZ2_UPDATE_S2_LASER:
    LD A,(EBUZ2_LASER_ACT)
    OR A
    RET Z
    LD A,(EBUZ2_LASER_HOLD_COUNTDOWN)
    OR A
    JR Z,EBUZ2_USL_RETRACT
    DEC A
    LD (EBUZ2_LASER_HOLD_COUNTDOWN),A
    RET
EBUZ2_USL_RETRACT:
    LD A,(EBUZ2_LASER_RETRACT_UNIT)
    ADD A,A
    ADD A,1
    LD C,A
    LD A,(EBUZ2_LASER_ROW)
    LD B,A
    CALL EBUZ2_CALC_ADDR
    LD B,0 : LD C,0
    CALL EBUZ2_WRITE2
    LD A,(EBUZ2_LASER_RETRACT_UNIT)
    OR A
    JR Z,EBUZ2_USL_DONE
    DEC A
    LD (EBUZ2_LASER_RETRACT_UNIT),A
    RET
EBUZ2_USL_DONE:
    XOR A
    LD (EBUZ2_LASER_ACT),A
    RET

; ============================================================================
; 1"フレーム"分の処理: 10プール(閉状態5+開状態5)の弾更新(常時)→
; ウェイト。開状態5プールは変形前は全スロットEBUZ2_SLOT_EMPTYのため
; 呼んでも無害(EBUZ2_UPDATE_SLOTが即RETするだけ)。
; 2026-09-20リセットでoscillation・発射シーケンスの呼び出しは削除
; (本体は発射後動かず、連射もしない)。
;
; (2026-09-20、実機フィードバック対応: "誰が乱射しろって指示したんだよ
; 以前のクソコードのこったままだろ" - 実機で本体・弾がガード帯まで
; 含め画面全体に無秩序に散乱する重大な不具合が発生)。以前このルーチンは
; ここでDI/EIを挟んでいたが、このファイルはH.TIMIフックを一切設置
; せず(BGM等の割り込み駆動サブシステムが存在しない)、割り込みを
; 有効化する必要がそもそも無いと判明。にもかかわらずEIで割り込みを
; 毎ティック再度有効化していたため、未設定のH.TIMI/BIOS割り込み経路
; 経由で本ROMの作業RAM(0F300h付近)が実機でのみ破壊されうる状態に
; なっていた(z80emu.pyは割り込みを一切発火しないため検出不可能 -
; このプロジェクト全体で繰り返し踏んできた「テスト全緑なのに実機でのみ
; 100%再現する」クラスの不具合と同型)。INIT冒頭のDIのまま最後まで
; 割り込みを一切有効化しないよう、このルーチンのDI/EIを完全に削除した。
; ============================================================================
EBUZ2_TICK:
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
    CALL EBUZ2_UPDATE_S2_MOVE
    CALL EBUZ2_UPDATE_S2_LASER
    CALL EBUZ2_SOUND_UPDATE
    CALL EBUZ2_FRAME_WAIT
    RET

; 登場の移動フェーズ専用: EBUZ2_ENTRY_STEP_HOLD_TICKS回だけEBUZ2_TICKを
; 呼ぶ(弾プールの更新を止めない待ち、1ティック=1行では速すぎて
; 「いきなり出現した」ようにしか見えないため)。
; 汎用版: IN: B=待ちたいティック数(1-255)。無印Ebuzの
; EBUZ_WAIT_TICKSと全く同じ設計(EBUZ2_TICKをB回呼ぶだけ、弾の移動は
; 止めない)。EBUZ2_ENTRY_HOLD(登場フェーズ専用、常にEBUZ2_ENTRY_
; STEP_HOLD_TICKS回)はこれの薄いラッパー。
EBUZ2_HOLD_N:
EBUZ2_HOLD_N_LOOP:
    PUSH BC
    CALL EBUZ2_TICK
EBUZ2_FRAME_TICK:                  ; テスト用: 「1ティック完了」の目印
    POP BC
    DJNZ EBUZ2_HOLD_N_LOOP
    RET

EBUZ2_ENTRY_HOLD:
    LD B,EBUZ2_ENTRY_STEP_HOLD_TICKS
    JR EBUZ2_HOLD_N

; ============================================================================
INIT:
    LD SP,STACKTOP
    DI
    CALL INIT32
    ; (2026-09-20、実機フィードバック対応: "何故かスポーン時に画面下部に
    ; 弾撃ちまくるコード入れてんだろうが" - 実機/openMSXで再現・特定した
    ; 真因) CALL INIT32はBIOS内部でEI+HALTによるvblank待ちを行うため、
    ; 呼び出し後はIFF1が1(割り込み許可)のまま戻ってくる(このファイルの
    ; 冒頭のDIは無効化される)。ここで再度DIしても、この直後から本体・弾の
    ; 描画で多用するWRTVRM/LDIRVM自体がBIOS内部で毎回EIし直すため
    ; (openMSXのbreakpointで実測確認済み: このDI実行直後は確かにIFF=0に
    ; なるが、数秒後には再びIFF=7[割り込み許可]に戻っている)、この
    ; ファイルの実行中は事実上ずっと割り込み許可状態のままになる。
    ; 念のためここでも再DIしておくが(害はない)、真の対策ではない。
    DI
    ; 真の原因はBIOS標準割り込みハンドラ(H.TIMIフックの手前で毎垂直
    ; 帰線ごとに走るキー走査・JIFFY更新等)が使うBIOSシステム変数領域
    ; と、このファイル自身の作業RAMが重なっていたこと。openMSXの
    ; watchpointで実測した結果、少なくとも0F352h-0F3F6h・0FBD9h-
    ; 0FBEFh・0FC9Eh-0FC9Fhの範囲がBIOSに書き換えられることを確認、
    ; 当時のEBUZ2作業RAM(0F300h-0F35Fh)がまさにこの範囲と衝突して
    ; いた。これが「本体の位置とは無関係な場所へ弾がスポーン直後から
    ; 出現し続ける」報告の直接原因 - 真の対策は本ファイルの作業RAM
    ; 定義(後方、EBUZ2_BODY_ROW等)を実測で無衝突と確認できた0F100h台
    ; へ全面移設したこと(詳細はそちらのコメント参照)。

    ; --- PSG R7ミキサー設定(2026-09-20「発射音追加 Ebuzと同じでいい」
    ; 対応): channel Aのノイズジェネレータのみ有効化(tone A/B/C・
    ; noise B/Cは無効のまま)。無印Ebuz(src/CYBER SHMUP.asm)と同じ
    ; DI/EIでOUTペアを保護する作法(このファイルは前述の通りBIOS内部の
    ; EIにより実質常時割り込み許可状態のため必須)。ポートA/B方向ビット
    ; (bit6-7='10')も同じく安全のため踏襲。 ---
    DI
    LD A,7 : OUT (PSG_ADDR),A
    LD A,0B7h : OUT (PSG_DATA),A
    EI

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

    ; レーザー用BGタイル2枚+専用カラー(「中央弾はレーザーに変える」対応)
    LD HL,LASER_L_TILE : LD DE,LASER_L_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,LASER_R_TILE : LD DE,LASER_R_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ2_LASER_COLOR_BYTE : LD DE,COLTBL+10 : LD BC,1 : CALL LDIRVM

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
    XOR A
    LD (EBUZ2_S2_OT_ROWS+0),A : LD (EBUZ2_S2_OT_ROWS+1),A : LD (EBUZ2_S2_OT_ROWS+2),A : LD (EBUZ2_S2_OT_ROWS+3),A
    LD (EBUZ2_S2_OT_ROWS+4),A : LD (EBUZ2_S2_OT_ROWS+5),A : LD (EBUZ2_S2_OT_ROWS+6),A : LD (EBUZ2_S2_OT_ROWS+7),A
    LD (EBUZ2_S2_IT_ROWS+0),A : LD (EBUZ2_S2_IT_ROWS+1),A : LD (EBUZ2_S2_IT_ROWS+2),A : LD (EBUZ2_S2_IT_ROWS+3),A
    LD (EBUZ2_S2_IT_ROWS+4),A : LD (EBUZ2_S2_IT_ROWS+5),A : LD (EBUZ2_S2_IT_ROWS+6),A : LD (EBUZ2_S2_IT_ROWS+7),A
    LD (EBUZ2_S2_C_ROWS+0),A  : LD (EBUZ2_S2_C_ROWS+1),A  : LD (EBUZ2_S2_C_ROWS+2),A  : LD (EBUZ2_S2_C_ROWS+3),A
    LD (EBUZ2_S2_C_ROWS+4),A  : LD (EBUZ2_S2_C_ROWS+5),A  : LD (EBUZ2_S2_C_ROWS+6),A  : LD (EBUZ2_S2_C_ROWS+7),A
    LD (EBUZ2_S2_IB_ROWS+0),A : LD (EBUZ2_S2_IB_ROWS+1),A : LD (EBUZ2_S2_IB_ROWS+2),A : LD (EBUZ2_S2_IB_ROWS+3),A
    LD (EBUZ2_S2_IB_ROWS+4),A : LD (EBUZ2_S2_IB_ROWS+5),A : LD (EBUZ2_S2_IB_ROWS+6),A : LD (EBUZ2_S2_IB_ROWS+7),A
    LD (EBUZ2_S2_OB_ROWS+0),A : LD (EBUZ2_S2_OB_ROWS+1),A : LD (EBUZ2_S2_OB_ROWS+2),A : LD (EBUZ2_S2_OB_ROWS+3),A
    LD (EBUZ2_S2_OB_ROWS+4),A : LD (EBUZ2_S2_OB_ROWS+5),A : LD (EBUZ2_S2_OB_ROWS+6),A : LD (EBUZ2_S2_OB_ROWS+7),A
    LD (EBUZ2_S2_ROW_CUR),A
    LD (EBUZ2_S2_MOVE_ACTIVE),A   ; 0=変形完了までは上下移動を起動しない
    LD (EBUZ2_S2_MOVE_DIR),A
    LD (EBUZ2_S2_MOVE_COUNTDOWN),A
    LD (EBUZ2_S2_MOVE_REACHED_MAX),A
    LD (EBUZ2_S2_MOVE_ROUNDTRIP_DONE),A
    LD (EBUZ2_S2_MOVE_REACHED_MIN),A
    LD (EBUZ2_TICK_COUNTER),A
    LD (EBUZ2_SND_TIMER),A
    LD (EBUZ2_LASER_ACT),A
    LD (EBUZ2_LASER_ROW),A
    LD (EBUZ2_LASER_RETRACT_UNIT),A
    LD (EBUZ2_LASER_HOLD_COUNTDOWN),A

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

    ; --- 発射後ホールド: 無印Ebuzの「初弾発射直後にその場で10ティック
    ; 静止してから次(変形)に入る」構造を移植(上のEBUZ2_VOLLEY1_HOLD_
    ; TICKS定義のコメント参照)。 ---
    LD B,EBUZ2_VOLLEY1_HOLD_TICKS : CALL EBUZ2_HOLD_N

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
    LD B,EBUZ2_RECOIL_HOLD_TICKS : CALL EBUZ2_HOLD_N
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
    LD B,EBUZ2_RECOIL_HOLD_TICKS : CALL EBUZ2_HOLD_N
EBUZ2_RECOIL_DONE:

    ; --- 変形: 閉状態(5行)を消去し、開状態Mk2-2(7行、row8-14)を
    ; 描画する。「変形時に1セルズレてる...上に1セル上げてくれ」指示
    ; により、開状態はEBUZ2_S2_ROW_TOP(=EBUZ2_ENTRY_TARGET_ROW_TOP-1、
    ; row8)を起点に描画し、閉状態(row_top+2=11)と開状態(row_top+3=11)
    ; の中心行を一致させる。EBUZ2_S2_ROW_CURはここで確定させる(この後の
    ; 中央→内側2門→外側2門の順次発射が発射行として読むため必須)が、
    ; 「変形後の交互発射を開始したら...往復だぞ」指示により上下移動
    ; 自体(EBUZ2_S2_MOVE_ACTIVE)はまだ起動しない - 本体は無制限交互
    ; 発射が始まる直前(EBUZ2_VOLLEY2_ALT_LOOP手前)まで、この変形直後の
    ; 位置(row8)で静止したまま。 ---
    LD A,EBUZ2_ENTRY_TARGET_ROW_TOP
    CALL EBUZ2_ERASE_BODY_AT
    LD A,EBUZ2_S2_ROW_TOP
    LD (EBUZ2_S2_ROW_CUR),A
    CALL EBUZ2_DRAW_S2_BODY_AT
    CALL EBUZ2_ENTRY_HOLD
EBUZ2_TRANSFORM_DONE:

    ; --- 変形後の発射: 当初は「中央から1発 内側2門から1発 外側2門
    ; から1発」の順次発射だったが、「中央弾はレーザーに変えるんで
    ; 変形までの中央弾は削除 中央から撃つのは上下動1周後のみに変更」
    ; 対応により、変形直後の中央弾は削除。以後は内側2門→外側2門の
    ; 2ウェーブのみ(中央弾は上下動1周完了後のレーザーとしてのみ発射
    ; される、EBUZ2_S2_STOP_SEQUENCE参照)。「変形後弾を撃つ前の
    ; ホールドを５Tick挿入」指示による静止ホールドは、最初に生き残る
    ; 発射(内側2門)の直前としてそのまま維持。 ---
    LD B,EBUZ2_VOLLEY2_PRE_FIRE_HOLD_TICKS : CALL EBUZ2_HOLD_N
EBUZ2_VOLLEY2_WAVE_C_DONE:
    LD B,EBUZ2_VOLLEY2_WAVE_HOLD_TICKS : CALL EBUZ2_HOLD_N
    CALL EBUZ2_FIRE_IT_BULLET
    CALL EBUZ2_FIRE_IB_BULLET
    CALL EBUZ2_SOUND_FIRE  ; 「交互発射もサウンド追加」対応
EBUZ2_VOLLEY2_WAVE_INNER_DONE:
    LD B,EBUZ2_VOLLEY2_WAVE_HOLD_TICKS : CALL EBUZ2_HOLD_N
    CALL EBUZ2_FIRE_OT_BULLET
    CALL EBUZ2_FIRE_OB_BULLET
    CALL EBUZ2_SOUND_FIRE  ; 「交互発射もサウンド追加」対応
EBUZ2_VOLLEY2_DONE:

; --- 「では次に内2門と外2門の無制限交互発射」(2026-09-20追加指示):
; 中央弾は変形直後には撃たなくなった(上下動1周後のレーザーのみ)。
; 以後は内側ペア(IT+IB)と外側ペア(OT+OB)をEBUZ2_VOLLEY2_WAVE_HOLD_
; TICKS間隔で永久に交互発射
; し続ける - 無印Ebuzの継続発射(EBUZ_TOPBOTTOM_ACTIVE/EBUZ_FIRE_SIDEに
; よる上下交代、EBUZ_FIRE_INTERVAL=2フレ交代)と同じ「固定間隔・無条件
; 発射・生存チェックなし」の考え方を、内・外の2門ペア単位でそのまま
; 適用したもの(無印Ebuzは1門ずつの交代だが、Mk2は「2門同時発射」を
; 1ユニットとして交代させる点のみが違う)。「交互発射するまでに15Tickの
; ウェイト挿入」→さらに追加指示「ウェイトを20Tickに」を受け、外側
; ペアの1発目発射完了から無制限交互発射の開始(2巡目の内側ペア)まで
; の間にEBUZ2_VOLLEY2_ALT_START_HOLD_TICKS(20)だけ静止ホールドを
; 挿む。加えて「リコイル動作を追加」指示により、発射したペアの行
; だけをEBUZ2_ROW_S2_INNER/OUTER_RECOILへ1セル右にずらして
; EBUZ2_RECOIL_HOLD_TICKS(1)保持→REST位置へ戻して同じく1tick保持、
; という無印Ebuzの継続発射リコイルと同じ手順を各発射ごとに行う。
; 「一応シーケンス指示しとく...変形後の交互発射を開始したら 画面2行目
; から下は5行目までを往復だぞ」指示、さらに「動き始めはワープすんな
; 上から来て中央で止まったんだから 停止位置からまず下に動け」訂正に
; より、この無制限交互発射の開始直前で上下往復(EBUZ2_UPDATE_S2_MOVE)
; を起動する。「ワープすんな」の通り本体の位置(row8、変形直後に
; 止まった位置)はそのまま動かさず、その場から往復を開始し、最初の
; 一歩は下方向(row8→row13→折り返して上へ)とする - それまで
; (変形直後〜中央/内側/外側の順次発射〜このホールド)は本体はrow8で
; 静止したまま。 ---
EBUZ2_VOLLEY2_ALT_START_HOLD_TICKS EQU 20  ; 「ウェイトを20Tickに」指示で15→20
    LD B,EBUZ2_VOLLEY2_ALT_START_HOLD_TICKS : CALL EBUZ2_HOLD_N
    ; --- 無制限交互発射の開始と同時に上下往復を起動: 本体の位置は
    ; 変えず(ワープさせない)、その場から下方向へ動き始める。 ---
    XOR A
    LD (EBUZ2_S2_MOVE_DIR),A       ; 0=下方向(row8→row13)から開始
    LD A,EBUZ2_S2_MOVE_INTERVAL_TICKS
    LD (EBUZ2_S2_MOVE_COUNTDOWN),A
    LD A,1
    LD (EBUZ2_S2_MOVE_ACTIVE),A
; (2026-09-20追加指示「上下移動を追加」対応): 本体が上下に動くように
; なったため、このリコイル演出の対象行もEBUZ2_S2_ROW_TOP固定値では
; なく、その瞬間のEBUZ2_S2_ROW_CUR(+各門の固定オフセット)から毎回
; 計算し直す(固定値のままだと本体が別の行へ移動した後もリコイルが
; 元の位置に描かれ続け、背景を壊してしまう)。
EBUZ2_VOLLEY2_ALT_LOOP:
    ; 1往復完了済みならここで交互連射ループを抜ける(この時点で本体は
    ; 既にMIN_ROWで静止・上下動も停止済み)。
    LD A,(EBUZ2_S2_MOVE_ROUNDTRIP_DONE)
    OR A
    JP NZ,EBUZ2_S2_STOP_SEQUENCE
    LD B,EBUZ2_VOLLEY2_WAVE_HOLD_TICKS : CALL EBUZ2_HOLD_N
    CALL EBUZ2_FIRE_IT_BULLET
    CALL EBUZ2_FIRE_IB_BULLET
    CALL EBUZ2_SOUND_FIRE  ; 「交互発射もサウンド追加」対応
    ; --- リコイル(内側ペア): IT(row ROW_CUR+1)・IB(row ROW_CUR+5)
    ; を1セル右へずらしてから元へ戻す。リコイル演出の間(HOLD_N経由で
    ; 数tick経過する)だけEBUZ2_S2_MOVE_ACTIVEを一旦止め、演出中に
    ; 本体が上下移動してROW_CURが変わり、REST復帰の描画先が実体と
    ; ズレる事故を防ぐ(ごく短時間の移動一時停止、体感上は問題ない
    ; はず)。 ---
    XOR A : LD (EBUZ2_S2_MOVE_ACTIVE),A
    LD A,(EBUZ2_S2_ROW_CUR) : ADD A,1 : LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_INNER_RECOIL : POP DE : LD BC,6 : CALL LDIRVM
    LD A,(EBUZ2_S2_ROW_CUR) : ADD A,5 : LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_INNER_RECOIL : POP DE : LD BC,6 : CALL LDIRVM
    LD B,EBUZ2_RECOIL_HOLD_TICKS : CALL EBUZ2_HOLD_N
    LD A,(EBUZ2_S2_ROW_CUR) : ADD A,1 : LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_INNER_REST : POP DE : LD BC,6 : CALL LDIRVM
    LD A,(EBUZ2_S2_ROW_CUR) : ADD A,5 : LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_INNER_REST : POP DE : LD BC,6 : CALL LDIRVM
    LD B,EBUZ2_RECOIL_HOLD_TICKS : CALL EBUZ2_HOLD_N
    CALL EBUZ2_S2_RESTORE_MOVE_ACTIVE
EBUZ2_VOLLEY2_ALT_INNER_DONE:              ; テスト用: 交互発射1周ぶんの内側完了地点
    LD B,EBUZ2_VOLLEY2_WAVE_HOLD_TICKS : CALL EBUZ2_HOLD_N
    CALL EBUZ2_FIRE_OT_BULLET
    CALL EBUZ2_FIRE_OB_BULLET
    CALL EBUZ2_SOUND_FIRE  ; 「交互発射もサウンド追加」対応
    ; --- リコイル(外側ペア): OT(row ROW_CUR)・OB(row ROW_CUR+6)
    ; を1セル右へずらしてから元へ戻す(同じ理由で上下移動を一時停止)。 ---
    XOR A : LD (EBUZ2_S2_MOVE_ACTIVE),A
    LD A,(EBUZ2_S2_ROW_CUR) : LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_OUTER_RECOIL : POP DE : LD BC,6 : CALL LDIRVM
    LD A,(EBUZ2_S2_ROW_CUR) : ADD A,6 : LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_OUTER_RECOIL : POP DE : LD BC,6 : CALL LDIRVM
    LD B,EBUZ2_RECOIL_HOLD_TICKS : CALL EBUZ2_HOLD_N
    LD A,(EBUZ2_S2_ROW_CUR) : LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_OUTER_REST : POP DE : LD BC,6 : CALL LDIRVM
    LD A,(EBUZ2_S2_ROW_CUR) : ADD A,6 : LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_OUTER_REST : POP DE : LD BC,6 : CALL LDIRVM
    LD B,EBUZ2_RECOIL_HOLD_TICKS : CALL EBUZ2_HOLD_N
    CALL EBUZ2_S2_RESTORE_MOVE_ACTIVE
EBUZ2_VOLLEY2_ALT_OUTER_DONE:              ; テスト用: 交互発射1周ぶんの外側完了地点
    JP EBUZ2_VOLLEY2_ALT_LOOP  ; ループ本体が長くなりJR射程(-128〜127)を超えたためJPに変更

; (2026-09-20「では一往復したら上下動停止して 交互連射も停止 15Tick
; 停止したら 中央から1発発射」対応) 1周完了(EBUZ2_S2_MOVE_ROUNDTRIP_
; DONE=1、上下動自体はEBUZ2_UPDATE_S2_MOVE側で既に停止済み)を検知
; したら、無制限交互発射のループ自体もここで抜けて停止する。
EBUZ2_S2_STOP_SEQUENCE:
    LD B,15 : CALL EBUZ2_HOLD_N
    CALL EBUZ2_FIRE_S2_LASER  ; 「中央弾はレーザーに変える」対応
    CALL EBUZ2_SOUND_FIRE
    ; --- リコイル(中央、「では中央発射のリコイル追加」対応):
    ; center row(ROW_CUR+3)を1セル右へずらしてから元へ戻す。この時点で
    ; 上下動は既に停止済み(MOVE_ACTIVE=0)のため、内側/外側リコイルの
    ; ような一時停止・復帰処理は不要。 ---
    LD A,(EBUZ2_S2_ROW_CUR) : ADD A,3 : LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_CENTER_RECOIL : POP DE : LD BC,6 : CALL LDIRVM
    LD B,EBUZ2_RECOIL_HOLD_TICKS : CALL EBUZ2_HOLD_N
    LD A,(EBUZ2_S2_ROW_CUR) : ADD A,3 : LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_CENTER_REST : POP DE : LD BC,6 : CALL LDIRVM
    LD B,EBUZ2_RECOIL_HOLD_TICKS : CALL EBUZ2_HOLD_N
EBUZ2_S2_LAP_SHOT_DONE:                    ; テスト用: 1周分の中央1発発射+リコイル完了地点
; (実機フィードバック対応「中央の弾撃ったあとのホールド消えてんじゃ
; ねえか」) ループ化した際、発射後すぐ次の周(上下動再開)へ移って
; いたため、発射前と対称のホールドが無くなっていた。発射後にも同じ
; 15Tickのホールドを入れ直す。
    LD B,15 : CALL EBUZ2_HOLD_N
; (2026-09-20「では以降上下動シーケンスのループ」対応) 中央から1発
; 撃ったら終わりではなく、上下動シーケンス(中央出発→下端→上端→
; 中央で停止→15Tick待ち→中央から1発発射→15Tick待ち)自体を丸ごと
; 無限に繰り返す。1周ぶんの状態(方向・カウントダウン・両端到達
; フラグ・完了フラグ)を全てリセットしてから、無制限交互発射ループの
; 先頭(EBUZ2_VOLLEY2_ALT_LOOP)へ戻る。ボディの位置(中央)は変えない
; (次の周もワープせずその場から下方向へ再出発する)。
    XOR A
    LD (EBUZ2_S2_MOVE_DIR),A
    LD (EBUZ2_S2_MOVE_REACHED_MAX),A
    LD (EBUZ2_S2_MOVE_REACHED_MIN),A
    LD (EBUZ2_S2_MOVE_ROUNDTRIP_DONE),A
    LD A,EBUZ2_S2_MOVE_INTERVAL_TICKS
    LD (EBUZ2_S2_MOVE_COUNTDOWN),A
    LD A,1
    LD (EBUZ2_S2_MOVE_ACTIVE),A
    JP EBUZ2_VOLLEY2_ALT_LOOP

EBUZ2_COLOR_BYTE:
    DB EBUZ2_COLOR

EBUZ2_BULLET_COLOR_BYTE:
    DB EBUZ2_BULLET_COLOR

EBUZ2_LASER_COLOR_BYTE:
    DB EBUZ2_LASER_COLOR

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

; レーザーの8x8タイル2枚(添付EbuzIIBeam_16x16.jsonの上半分16x8を
; 左右8x8に切り出したもの、Pythonでビット単位抽出・bit7=左端列)。
LASER_L_TILE:
    DB 0,128,197,111,57,20,32,16
LASER_R_TILE:
    DB 33,67,166,28,136,224,36,16
