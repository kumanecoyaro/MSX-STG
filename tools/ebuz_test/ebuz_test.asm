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
;     6pxで"→その7"8pxで")で単純な固定速度へ再変更・さらに増速、
;     交互方式は撤去済み(詳細はEBUZ_BULLET_SPEEDのEQU定義コメント
;     参照)。
;
; (2026-09-13追記その7、実機フィードバック対応、上下弾の継続発射化):
; "8pxで 初弾のホールドタイムは で、上下弾は交互に撃ち続けろ 2フレ
; 交代 打つときは反動を見せたいんで 上下の3セル分を1セル右に 打ったら
; 元位置に戻せ"。state2の上下弾(旧: 変形+0.5秒待ち後に1回だけ同時発射
; して終わり)を、以後2ティックごとに上下交互に撃ち続ける継続発射へ
; 変更(初弾=Ebuz1弾のホールドタイム自体は無変更)。発射のたびに、その
; 側の翼帯(A,B,Cの3セル)を1セル右へ「反動」表示し、1ティック後に元の
; 位置へ戻す。詳細はEBUZ_UPDATE_TOPBOTTOM_FIRE/EBUZ_ROW_0ABC_REST/
; EBUZ_ROW_0ABC_RECOILのコメント参照。
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
; (2026-09-13追記その7、実機フィードバック対応: "8pxで") さらに8pxへ。
EBUZ_BULLET_SPEED EQU 8
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

; (2026-09-13追記その7、実機フィードバック対応: "初弾のホールドタイムは
; で、上下弾は交互に撃ち続けろ 2フレ交代 打つときは反動を見せたいんで
; 上下の3セル分を1セル右に 打ったら元位置に戻せ"): state2の上下弾
; (旧: Ebuz2変形+0.5秒待ち後に1回だけ同時発射して終わり)を、以後
; 2ティックごとに上下交互に撃ち続ける継続発射へ変更。発射のたびに、
; 発射した側の翼帯(A,B,C の3セル)を1セル右へ「反動」表示し、1ティック
; 後に元位置へ戻す。continuous-fireはEBUZ_TOPBOTTOM_ACTIVE=1の間だけ
; EBUZ_TICKから呼ばれる(state1の間・state2形成前は従来通り一切
; 発火しない)。設計はEBUZ_FIRE_SIDE(次に撃つ側)+EBUZ_FIRE_COUNTDOWN
; (次の発射までの残りティック数)という単一の共有ターン制御による、
; 文字通りの「交互に・2フレ交代」("2フレ交代"=カウントダウンの初期値)。
;
; (2026-09-13追記その8、実機フィードバック対応: "撃った弾戻して交互に
; 発射してどうすんだバカ 撃った弾は画面外に消えるまで戻さねえ"):
; その7時点の実装はカウントダウンが0になった瞬間、その側のスロットが
; まだ画面上に生きていても無条件で原点へ上書きしてしまう誤りだった。
; **修正はこの1点のみ**(ターン制御自体の構造は変更しない): カウント
; ダウンが0になった時、対象スロットがまだ非表示(SPR_HIDE_Y)でなければ
; まだ発射せず、カウントダウンを1に戻して次のティックで再チェックする
; だけ(側の交代=EBUZ_FIRE_SIDEの反転もまだ行わない)。対象スロットが
; 既に非表示(=画面外に消えた)なら、従来通り原点へ再発射し反動を表示、
; 側を交代してカウントダウンをEBUZ_FIRE_INTERVALへ戻す。
;
; (2026-09-13、ユーザー叱責を受けての再設計方針の訂正: "一つ前は
; ウェイトと弾が戻るのを除けばシーケンス自体は正しかったんだよ"
; "お前の解釈は毎度毎度 指示を無視して勝手に手順変えるから まともに
; 動かねんだろうが"): 直前のRound(122)ではこの「共有ターン変数」設計
; 自体を「各スロット完全独立([下側だけ初回に1回限りの位相差]、以後は
; 上下とも自分の非表示状態だけを見て再発射)」という別の構造へ勝手に
; 作り替えていたが、これは指示にない独自解釈だった。ユーザーの言う
; 「シーケンス自体は正しかった」はこの共有ターン制御(EBUZ_FIRE_SIDE/
; EBUZ_FIRE_COUNTDOWNによる文字通りの「交互に・2フレ交代」)を指すと
; 判断し、Round121の構造へ戻した上で、実際に指摘された不具合(生きて
; いる弾の強制リセット)だけをピンポイントで修正する最小修正へ変更した。
EBUZ_TOPBOTTOM_ACTIVE  EQU 0F35Ch  ; 1 byte: 0=まだ非活性、1=継続発射中
EBUZ_FIRE_SIDE         EQU 0F35Dh  ; 1 byte: 次に撃つ側(0=上/1=下)
EBUZ_FIRE_COUNTDOWN    EQU 0F35Eh  ; 1 byte: 次の発射(判定)までの残りティック数
EBUZ_RECOIL_SIDE       EQU 0F35Fh  ; 1 byte: 現在反動表示中の側(0/1)
EBUZ_RECOIL_COUNTDOWN  EQU 0F360h  ; 1 byte: 反動が元に戻るまでの残りティック数(0=反動なし)
EBUZ_FIRE_INTERVAL     EQU 2       ; "2フレ交代"
EBUZ_RECOIL_DURATION   EQU 1       ; 反動表示の持続ティック数(打ったら次のティックで元位置)

; (2026-09-13追記その8、実機フィードバック対応: "しかもお前ホールド
; タイムをBuz1で打った後に入れてるじゃねえか 弾を表示してホールドだって
; 言っただろが"): bullet0(Ebuz1弾)のホールドタイムの意味を訂正。旧実装
; は「非表示のまま0.5秒待ってから初めて表示(発射)」だったが、正しくは
; 「Ebuz1出現と同時に弾を表示し、その位置で0.5秒静止(ホールド)させて
; から実際に飛ばし始める」。EBUZ_BULLET0_HOLDING=1の間、EBUZ_TICKは
; スロット0(bullet0)のEBUZ_UPDATE_BULLET呼び出しをスキップする(表示は
; されたまま、移動だけ止める)。
EBUZ_BULLET0_HOLDING   EQU 0F361h  ; 1 byte: 1=ホールド中(表示のみ、移動しない)、0=通常飛行中

; (2026-09-13、実機フィードバック対応: "最初の弾止まったままじゃねえかよ
; マジでスプライトの扱いも知らねえしよ ナンバー使い回したら消えるに
; 決まってんだろうが 画面内の弾のスプライトナンバーは全て違ってる
; 必要があんだよ 画面内に10発なら1から10までをループして使わなきゃ
; きえんだよアホが"): これまでは論理的な弾(スロット0=初弾/スロット1=
; 上/スロット2=下)ごとに固定のHWスプライト番号(SPRATRの物理オフセット
; 0/4/8)を割り当て、同じ弾が消えて再発射されるたびに**同じ物理番号を
; 使い回して**いた。これがまさに指摘された不具合の原因と判断し、
; 新しい発射(再発射含む)のたびに物理スプライト番号をローテーション
; (0→1→2→...→9→0→...)で割り当て直す方式に変更する。論理シャドウ
; (EBUZ_SPR_SHADOW、Y/X/pattern/colorの実データ)は従来通り3枠のまま、
; 各枠が「現在どの物理HWスプライト番号を使っているか」を別途
; EBUZ_PHYS_SLOTに記録し、毎ティックの反映(旧: 固定オフセットへの
; 一括LDIRVM)もこの物理番号ベースの個別LDIRVMへ変更する。
EBUZ_PHYS_SLOT_COUNT EQU 10  ; "画面内に10発なら1から10まで"に対応、物理スロット0-9をローテーション使用
EBUZ_PHYS_SLOT       EQU 0F362h  ; 3 bytes: 論理スロット0/1/2それぞれの現在の物理HWスプライト番号(0-9)
EBUZ_NEXT_PHYS_SLOT  EQU 0F365h  ; 1 byte: 次に割り当てる物理スロット番号(ローテーションカウンタ)

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

; 物理HWスプライト番号を1つローテーションで割り当てる(2026-09-13、
; "スプライトナンバーは全て違ってる必要がある...1から10までをループ
; して使わなきゃ消える"対応)。戻り値: A=割り当てた番号(0-9)。
; EBUZ_NEXT_PHYS_SLOTを(A+1) mod EBUZ_PHYS_SLOT_COUNTへ進める。
EBUZ_ALLOC_PHYS_SLOT:
    LD A,(EBUZ_NEXT_PHYS_SLOT)
    LD B,A                       ; B = 今回割り当てる番号(戻り値用に保持)
    INC A
    CP EBUZ_PHYS_SLOT_COUNT
    JR C,EBUZ_APS_OK
    XOR A
EBUZ_APS_OK:
    LD (EBUZ_NEXT_PHYS_SLOT),A
    LD A,B
    RET

; 論理シャドウ1枠(4byte: Y,X,pattern,color)を、指定した物理HW
; スプライト番号のSPRATR位置へ書き込む。
; IN: A=物理スロット番号(0-9)、HL=論理シャドウの先頭アドレス
EBUZ_FLUSH_ONE:
    ; NOTE: このアセンブラはEX DE,HLに対応していないため、DE<->HLの
    ; 交換はLD D,H:LD E,Lの2命令で代替する。
    PUSH HL                      ; HL(シャドウ元アドレス)を退避
    LD H,0
    LD L,A
    ADD HL,HL                    ; *2
    ADD HL,HL                    ; *4 -> HL=物理スロット*4
    LD DE,SPRATR
    ADD HL,DE                    ; HL=SPRATR+物理スロット*4(書き込み先)
    LD D,H
    LD E,L                       ; DE=書き込み先
    POP HL                       ; HL=シャドウ元アドレス(復元)
    LD BC,4
    CALL LDIRVM
    RET

; 論理シャドウ3枠すべてを、それぞれの現在の物理スロットへ反映する
; (旧: EBUZ_SPR_SHADOW->SPRATRの固定12byte一括LDIRVMを置き換え)。
EBUZ_FLUSH_ALL:
    LD A,(EBUZ_PHYS_SLOT+0)
    LD HL,EBUZ_SPR_SHADOW+0
    CALL EBUZ_FLUSH_ONE
    LD A,(EBUZ_PHYS_SLOT+1)
    LD HL,EBUZ_SPR_SHADOW+4
    CALL EBUZ_FLUSH_ONE
    LD A,(EBUZ_PHYS_SLOT+2)
    LD HL,EBUZ_SPR_SHADOW+8
    CALL EBUZ_FLUSH_ONE
    RET

; 1"フレーム"分の処理をまとめたもの: 弾3枠を更新→(継続発射有効なら)
; 上下弾の継続発射処理→VRAMへ反映→ウェイト。EBUZ_WAIT_TICK系と
; EBUZ_MAINLOOPの両方から共有で呼ばれる(2026-09-13追記その3、
; 「待ち時間中は弾が動かない」構造的バグの修正 - 発射前の弾は
; EBUZ_UPDATE_BULLET冒頭のSPR_HIDE_Yチェックで自動的にスキップされる
; ので、まだ発射されていないスロットに対して呼んでも安全)。
EBUZ_TICK:
    DI
    ; bullet0(スロット0)はEBUZ_BULLET0_HOLDING中は移動させない
    ; (2026-09-13追記その8、"弾を表示してホールドだって言っただろが")
    LD A,(EBUZ_BULLET0_HOLDING)
    OR A
    JR NZ,EBUZ_TICK_SKIP_B0
    LD IX,EBUZ_SPR_SHADOW   : CALL EBUZ_UPDATE_BULLET
EBUZ_TICK_SKIP_B0:
    LD IX,EBUZ_SPR_SHADOW+4 : CALL EBUZ_UPDATE_BULLET
    LD IX,EBUZ_SPR_SHADOW+8 : CALL EBUZ_UPDATE_BULLET
    LD A,(EBUZ_TOPBOTTOM_ACTIVE)
    OR A
    CALL NZ,EBUZ_UPDATE_TOPBOTTOM_FIRE
    CALL EBUZ_FLUSH_ALL
    EI
    CALL EBUZ_FRAME_WAIT
    RET

; 上下弾の継続発射処理(2026-09-13、Round121の共有ターン制御方式へ復元+
; 最小修正)。EBUZ_TOPBOTTOM_ACTIVE=1の間、EBUZ_TICKから毎回呼ばれる。
; (1)反動表示中なら1ティック後に元位置へ戻す。(2)発射カウントダウンが
; 0になったら、次に撃つ側(EBUZ_FIRE_SIDE)のスロットが既に非表示
; (=画面外に消えた)かを確認する - 生きている弾を強制リセットしない
; ための唯一の追加チェック(Round122で発見された不具合の修正点)。まだ
; 生きているならカウントダウンを1へ戻して次のティックで再チェックする
; だけで側は交代しない。既に消えていれば、原点から再発射(スロット1=
; 上/スロット2=下)し、その側の翼帯に反動を表示、側を反転しカウント
; ダウンをEBUZ_FIRE_INTERVALへ戻す。
EBUZ_UPDATE_TOPBOTTOM_FIRE:
    ; --- 反動表示の自動解除 ---
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
    ; --- 次の発射(判定)までのカウントダウン ---
    LD A,(EBUZ_FIRE_COUNTDOWN)
    DEC A
    LD (EBUZ_FIRE_COUNTDOWN),A
    RET NZ
    ; --- カウントダウン0: 次に撃つ側のスロットが既に非表示か確認 ---
    ; (生きている弾は強制リセットしない - 唯一の追加チェック)
    LD A,(EBUZ_FIRE_SIDE)
    OR A
    JR NZ,EUTF_CHECK_BOTTOM_SLOT
    LD A,(EBUZ_SPR_SHADOW+4)        ; スロット1(上)のY
    JR EUTF_CHECK_SLOT_Y
EUTF_CHECK_BOTTOM_SLOT:
    LD A,(EBUZ_SPR_SHADOW+8)        ; スロット2(下)のY
EUTF_CHECK_SLOT_Y:
    CP SPR_HIDE_Y
    JR Z,EUTF_DO_FIRE
    ; まだ生きている: 側は交代せず、次のティックで再チェック
    LD A,1
    LD (EBUZ_FIRE_COUNTDOWN),A
    RET
EUTF_DO_FIRE:
    LD A,EBUZ_FIRE_INTERVAL
    LD (EBUZ_FIRE_COUNTDOWN),A
    ; --- 発射(側に応じてスロット1/2を原点へ再セット+反動表示) ---
    LD A,(EBUZ_FIRE_SIDE)
    OR A
    JR NZ,EUTF_FIRE_BOTTOM
    LD HL,EBUZ_SPR_BULLET23 : LD DE,EBUZ_SPR_SHADOW+4 : LD BC,4 : LDIR
    ; 新しい発射のたびに物理HWスプライト番号を新規割り当て("ナンバー
    ; 使い回したら消える"対応、2026-09-13)
    CALL EBUZ_ALLOC_PHYS_SLOT
    LD (EBUZ_PHYS_SLOT+1),A
    LD HL,EBUZ_ROW_0ABC_RECOIL : LD DE,01838h : LD BC,5 : CALL LDIRVM
    JR EUTF_FIRE_DONE
EUTF_FIRE_BOTTOM:
    LD HL,EBUZ_SPR_BULLET23+4 : LD DE,EBUZ_SPR_SHADOW+8 : LD BC,4 : LDIR
    CALL EBUZ_ALLOC_PHYS_SLOT
    LD (EBUZ_PHYS_SLOT+2),A
    LD HL,EBUZ_ROW_0ABC_RECOIL : LD DE,01898h : LD BC,5 : CALL LDIRVM
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
; 止めない待ち」- 旧来の素のビジーウェイト(EBUZ_DELAY等)を置き換える。
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

    ; 論理シャドウ3枠とも非表示で初期化(RAM側、まだVRAMには反映しない)。
    LD HL,EBUZ_SPR_INIT : LD DE,EBUZ_SPR_SHADOW : LD BC,12 : LDIR

    ; 物理HWスプライト0-9番を全て非表示で初期化し、10番目をSAT終端
    ; (SPR_TERM_Y)にする(2026-09-13、"スプライトナンバーは全て違って
    ; る必要がある...1から10までをループして使わなきゃ消える"対応 -
    ; 論理弾3枚を固定の物理番号に紐付けず、発射のたびにローテーションで
    ; 新しい物理番号を割り当てる方式に変更したため、あらかじめ物理
    ; スロット0-9すべてを非表示状態で初期化しておく必要がある)。
    LD HL,EBUZ_SPR_ALL_HIDDEN : LD DE,SPRATR : LD BC,40 : CALL LDIRVM
    LD HL,EBUZ_SPR_TERM : LD DE,SPRATR+40 : LD BC,4 : CALL LDIRVM

    ; 論理スロット0/1/2の初期物理番号を仮に0/1/2とし(まだどれも発射
    ; されていないため実害なし)、次回割り当ては3番から開始する。
    LD A,0 : LD (EBUZ_PHYS_SLOT+0),A
    LD A,1 : LD (EBUZ_PHYS_SLOT+1),A
    LD A,2 : LD (EBUZ_PHYS_SLOT+2),A
    LD A,3 : LD (EBUZ_NEXT_PHYS_SLOT),A

    ; 上下弾の継続発射状態を非活性で初期化(2026-09-13追記その7/その8、
    ; RAM初期化漏れ防止のためEBUZ_FIRE_SIDE/EBUZ_RECOIL_SIDEも含め
    ; 全ワークエリアを明示的にゼロクリアする)
    XOR A
    LD (EBUZ_TOPBOTTOM_ACTIVE),A
    LD (EBUZ_FIRE_SIDE),A
    LD (EBUZ_FIRE_COUNTDOWN),A
    LD (EBUZ_RECOIL_SIDE),A
    LD (EBUZ_RECOIL_COUNTDOWN),A
    LD (EBUZ_BULLET0_HOLDING),A

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
    ; Ebuz1出現と同時に弾(BULLET_FULL、スロット0、X=16px左へ)を表示し、
    ; その位置で0.5秒間静止(ホールド)させてから実際に飛ばし始める
    ; (旧実装は逆に「非表示のまま0.5秒待ってから表示」だった)。
    LD HL,EBUZ_SPR_BULLET1 : LD DE,EBUZ_SPR_SHADOW : LD BC,4 : LDIR
    ; 発射のたびに物理HWスプライト番号を新規割り当て(2026-09-13、
    ; "ナンバー使い回したら消える"対応)
    CALL EBUZ_ALLOC_PHYS_SLOT
    LD (EBUZ_PHYS_SLOT+0),A
    LD A,(EBUZ_PHYS_SLOT+0)
    LD HL,EBUZ_SPR_SHADOW
    CALL EBUZ_FLUSH_ONE
    LD A,1
    LD (EBUZ_BULLET0_HOLDING),A

    ; --- 0.5秒ホールド(EBUZ_WAIT_TICKS経由、この間EBUZ_TICKがスロット0の ---
    ; 移動をスキップするので表示されたまま静止し続ける)。
    LD B,29
    CALL EBUZ_WAIT_TICKS

    ; --- ホールド終了、実際に飛び始める ---
    XOR A
    LD (EBUZ_BULLET0_HOLDING),A
EBUZ_STATE1_DONE:

    ; --- state2形成までの間(旧EBUZ_DELAY x2、約1.76秒相当)。 ---
    ; ここが今回の実機フィードバック対応の核心: この待ちの間、
    ; bullet0は既に発射済みなのでEBUZ_WAIT_TICKS経由で継続して左へ
    ; 移動し続ける(旧実装はここで完全静止していたため、bullets1/2が
    ; 発射される瞬間に3発とも本体のそばへ集まって見えていた)。
    LD B,102
    CALL EBUZ_WAIT_TICKS

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

    ; --- "Ebuz2に変形後...同じく0.5秒維持して"(2026-09-13追記) ---
    ; ここもEBUZ_WAIT_TICKS経由なのでbullet0は引き続き移動を続ける
    ; (この時点でbullet0は既に画面外へ消えているはず、下記の較正コメント
    ; 参照)。
    LD B,29
    CALL EBUZ_WAIT_TICKS

    ; --- "上下弾は交互に撃ち続けろ 2フレ交代"(2026-09-13、Round121の ---
    ; 共有ターン制御方式へ復元): 継続発射モードを起動。初弾(上側)は
    ; 次のEBUZ_TICKで即座に発射されるようFIRE_COUNTDOWN=1とする
    ; (以後はEBUZ_FIRE_INTERVALで2ティックおきに交互発射、ただし
    ; 生きている弾がある間は待つ)。
    XOR A
    LD (EBUZ_FIRE_SIDE),A          ; 0=まず上側から
    LD A,1
    LD (EBUZ_FIRE_COUNTDOWN),A     ; 次のティックで即発射判定
    LD A,1
    LD (EBUZ_TOPBOTTOM_ACTIVE),A
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
; 2026-09-13追記その7("打つときは反動を見せたいんで 上下の3セル分を
; 1セル右に 打ったら元位置に戻せ"): col24-28の5byte(col28は反動時
; だけC タイルが入る予備セル)。静止時REST=[空,A,B,C,空]、反動時
; RECOIL=[空,空,A,B,C](A,B,Cの3セルがまるごと1セル右へシフト)。
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

; 物理HWスプライト0-9番全ての起動時初期値(全て非表示、2026-09-13、
; "スプライトナンバーは全て違ってる必要がある...1から10までをループ"
; 対応の物理スロットプール)。
EBUZ_SPR_ALL_HIDDEN:
    DB SPR_HIDE_Y,0,0,0
    DB SPR_HIDE_Y,0,0,0
    DB SPR_HIDE_Y,0,0,0
    DB SPR_HIDE_Y,0,0,0
    DB SPR_HIDE_Y,0,0,0
    DB SPR_HIDE_Y,0,0,0
    DB SPR_HIDE_Y,0,0,0
    DB SPR_HIDE_Y,0,0,0
    DB SPR_HIDE_Y,0,0,0
    DB SPR_HIDE_Y,0,0,0

; state1発射時の弾1(スロット0): BULLET_FULL、Y=16(暫定)、
; X=176(=192-16、2026-09-13追記で16px左へ移動)
EBUZ_SPR_BULLET1:
    DB EBUZ_BULLET1_STORED_Y,EBUZ_BULLET1_X,BULLET_FULL_CODE,EBUZ_BULLET_COLOR

; state2発射時の弾2/弾3(スロット1,2): BULLET_HALF、Y=0px/24px、X=192
EBUZ_SPR_BULLET23:
    DB EBUZ_BULLET2_STORED_Y,EBUZ_BULLET_X,BULLET_HALF_CODE,EBUZ_BULLET_COLOR
    DB EBUZ_BULLET3_STORED_Y,EBUZ_BULLET_X,BULLET_HALF_CODE,EBUZ_BULLET_COLOR
