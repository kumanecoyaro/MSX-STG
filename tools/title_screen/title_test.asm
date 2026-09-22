; Title-screen bank test (round39, "バンクテストをしたいので...新バンク
; には必要な初期化処理を実装した上で PUSH STARTと表示しStage1とStage2
; のボスを適当に表示して ボタンが押されたらStage1へトランポリンする
; ように"). This is a genuinely new, THIRD bank pair (title/PUSH START)
; added to the existing 2-pair (Stage1, Stage2) ASCII16 layout - see
; tools/bankswitch_poc/build_full_rom.py for how the 3 pairs actually
; get laid out into one ROM and which becomes the boot target.
;
; Self-contained and independently assemblable/testable (own
; build_test.py), same convention as tools/stage2_combined/
; combined_test.asm - this file never needs Stage1/Stage2's own source
; touched, and vice versa.
;
; round43("添付ファイルはスクリーン2用のSC2ファイル これをタイトル画面に
; 変更 但し簡単な圧縮をかけてくれ MSXでも使える程度のデコードが軽い物"):
; round39の"適当な"SCREEN1プレースホルダー(Stage1/Stage2ボスの静止
; 表示+PUSH STARTテキスト)を完全に置き換え、ユーザー提供の本物の
; SCREEN2タイトルアート(tools/title_screen/assets/Title.SC2、BSAVE形式
; VRAMダンプ)をSCREEN2モードへ切り替えた上でそのまま表示する。
; アート自体はtools/title_screen/title_bg_gen.pyが自前のRLE(詳細は
; そのファイル自身のコメント参照)で圧縮してASMへ埋め込み、ここでは
; そのRLEストリームをVRAMへ直接ストリーム展開するだけ(展開先アドレス
; はVDPのオートインクリメントに任せ、CPU側でVRAMアドレスを個別に
; 管理する必要が無い設計)。
    ORG 4000h

INIT32   EQU 006Fh
INIGRP   EQU 0072h
LDIRVM   EQU 005Ch
WRTVRM   EQU 004Dh
WRTVDP   EQU 0047h
GTTRIG   EQU 00D8h
PSG_ADDR EQU 0A0h
PSG_DATA EQU 0A1h
VDP_ADDR EQU 099h
VDP_DATA EQU 098h

    DB "AB"
    DW INIT
    DW 0,0,0
    DS 6,0

STACKTOP EQU 0F380h

; SCREEN1/SCREEN2共通のBIOSデフォルトVRAMベースアドレス(両モードとも
; 同じ基準アドレスを使い、SCREEN2はパターン/カラーの各テーブルが
; 単に大きくなる[各6144バイト、3分割]だけ - Stage1/Stage2が使う値と
; 同一)。
NAMTBL EQU 1800h
COLTBL EQU 2000h
SPRATR EQU 1B00h
SPRPAT EQU 3800h

; RAM-resident bank-switch trampoline (see tools/bankswitch_poc/
; build_full_rom.py's own TRAMPOLINE_PATCH for the identical mechanism
; Stage1 uses) - this bank is the new boot target (bank0/window A,
; bank1/window B), so it installs its OWN copy rather than relying on
; one only Stage1's INIT would otherwise set up.
BANKSWITCH_TRAMPOLINE_RAM EQU 0F200h

; (2026-09-12、"タイトル表示からMission 1表示の間に差し込んで10回
; ループでMission 1表示に"、続けて"別に割り込みで同期取る必要はないぞ
; 適当にNopループでいい3フレ分の"): SCREEN3画像スライドショー用のRAM。
; SHADOW_PGT(2048byte)はtools/screen3_test/screen3_test.asmと同じ
; 「現在のPGTの実体、差分[XOR]適用先」。フレーム待ち(画像の切り替わり
; タイミング)は割り込み/JIFFY系に一切依存しない単純なZ80クロック
; 直接カウントのbusy-wait(src/CYBER SHMUP.asmのMISSION_DELAY_3SEC等と
; 同じ考え方)で実装する(以前追加したSCREEN3_TICKは撤回)。
SHADOW_PGT   EQU 0E800h

; (2026-09-12、実機フィードバック"表示は出来た だが音2回鳴らして
; 1コマじゃねえんだよ 音は割り込みで鳴らしてんだろうが 鳴らしながら
; アニメするんだよ"): 上記のフレーム待ちとは別に、確認音自体は
; H.TIMI駆動のバックグラウンドループへ変更する(combined_test.asmの
; BGM_TICKと同じ設計 - 画像の切り替わりごとに毎回ブロッキング呼び出し
; するのではなく、アニメーション全体を通じて割り込みで鳴り続ける)。
; SC3_CONFIRM_TICKS(confirm_beep_gen.py生成、53行×4byte)を辿る
; ポインタ/タイマー/残り行数。
SC3_CT_PTR       EQU 0E7F8h   ; word: 次に読む行へのポインタ
SC3_CT_TIMER     EQU 0E7FAh   ; word(下位byteのみ実際に使うが16bit演算で
                              ; 読み書きするため2byte確保): 現在の行の残りtick数
SC3_CT_ROWS_LEFT EQU 0E7FCh   ; byte: テーブル末尾までの残り行数(0で先頭へループ)
; (2026-09-13、"ではボーダーカラーの点滅をサウンドと同期して 削除前の
; 実装と同じだ"): PLAY_CONFIRM_BEEP(タイトルボタン押下音)のBORDER_
; TABLE(REDGRAD、53要素・CONFIRM_STEPSと1:1対応)をSC3_CONFIRM_TICK
; からも辿るための専用ポインタ。SC3_CT_PTRと全く同じ「新パス開始時に
; 先頭へ、1行進むたびに+1」という歩き方だが、PLAY_CONFIRM_BEEPのIX
; (1byte/行)とは違いSC3_CONFIRM_TICKS自体が4byte/行のテーブルなので、
; 同じHLでは共有できず別ポインタが必要。
SC3_CT_BORDER_PTR EQU 0E7FDh  ; word: BORDER_TABLE上の次に読む位置
; (2026-09-13、"で、サウンドがデューティ比かかってない 前は50%だった
; はず"): SC3_CONFIRM_TICKは元々「行をロードした瞬間だけR9へ音量を
; 書き、以後は行の残りtickをただ減算するだけ」の設計で、confirm_
; beep_gen.py自身のコメント通りデューティ比を意図的に省略していた。
; PLAY_CONFIRM_BEEP(タイトルボタン押下版)の「1行=ON半区間+OFF半区間の
; busy-wait」と違い、こちらはH.TIMI駆動(1回の呼び出し=1tick)のため
; 行内でON/OFFを分割する余地が無い。Round41のBGMデューティ(free-
; runningな位相カウンタをANDマスクでゲート判定)と同じ考え方を採用し、
; 行の残りtick数に関係なく毎tick位相を1進め、その最下位ビットで
; ON/OFFを交互に切り替える(50%duty、mask=1)。SC3_CT_VOLは現在の行の
; 音量(行ロード時にのみ更新)を保持、SC3_CT_PHASEは呼び出しごとに
; +1する自由継続カウンタ。
SC3_CT_VOL       EQU 0F000h   ; byte: 現在の行の音量(行ロード時のみ更新)
SC3_CT_PHASE     EQU 0F001h   ; byte: デューティ50%用の自由継続位相カウンタ
; (2026-09-13、"ではアニメ中にボタン押されたらMission 1表示にスキップ"):
; RUN_SCREEN3_SLIDESHOW開始時点のSPを退避しておき、アニメ中(=毎フレーム
; 待ちのWAIT_1_FRAME_UNIT)でボタン押下を検知したらSPをここへ強制的に
; 巻き戻してRUN_SCREEN3_SLIDESHOW末尾の後片付け(PSGミュート・ボーダー
; 黒復帰)ブロックへ直接JPする - 呼び出し階層(SHOW_SC3_IMGxやWAIT_
; N_FRAMES等)を全てスタック操作1つで一気に抜けられる。SC3_SKIP_ARMEDは
; 「アニメ開始直後、まだ最初の押しっぱなしボタンが離されていない」間は
; スキップを無視するデバウンスフラグ(一度両トリガーが0になるのを
; 確認してから1にする) - これが無いとアニメ開始のボタン押下がそのまま
; 継続していた場合、1コマも表示されずに即スキップしてしまう。
SC3_SKIP_ARMED   EQU 0F002h   ; byte: 0=まだ武装前(初期押しっぱなし無視)、1=武装済み
SC3_SAVED_SP     EQU 0F003h   ; word: RUN_SCREEN3_SLIDESHOW開始時点のSP
; (2026-09-13、"サウンドが最後尻切れで止まってるので9回鳴らしたら音止めて"):
; SC3_CONFIRM_TICKは53行の確認音メロディを末尾に達したら無条件に先頭へ
; ループし続ける設計のため、アニメ終了/スキップのタイミングと同期しておらず
; 曲の途中で強制ミュートされ尻切れになっていた。新パス開始のたびに1回だけ
; カウントし、SC3_CT_MAX_PASSES回再生し終えたら以後は明示的にミュート
; したまま何もしない停止状態へ移行する。
SC3_CT_PASS      EQU 0F005h   ; byte: 現在までに開始したメロディの再生回数
SC3_CT_MAX_PASSES EQU 9        ; 最大再生回数(これに達したら以後は無音のまま停止)

; global bank indices in the final ROM (see build_full_rom.py's own
; layout comment) - title=bank0/1 (this file), Stage1=bank2/3,
; Stage2=bank4/5. Stage1's own INIT lives at 4010h (same relative
; offset this file's own INIT does, and Stage2's - all 3 share the
; identical 16-byte "AB" header layout at ORG 4000h).
STAGE1_BANK_A EQU 2
STAGE1_BANK_B EQU 3
STAGE1_INIT   EQU 04010h

; (2026-09-07、"タイトル画面でAボタンスタートならゲームオーバーあり、
; Bボタンならゲームオーバー無しに これはテスト用なのでBはあとAと同様に
; ゲームオーバー有りにする"): src/CYBER SHMUP.asmのGAMEOVER_ENABLED
; (同じ物理アドレス、値は必ず一致させること)。RAM(0xC000-0xFFFF)は
; バンク切替を跨いで物理的に共有されるフラットな領域であることを
; 利用し、Stage1・Stage2両方がこの1バイトを直接参照する
; (GFEnding[Stage2]方式でのSTAGE1_SCORE直接参照と同じ手法)。
GAMEOVER_ENABLED EQU 0F235h

INIT:
    LD SP,STACKTOP

    ; --- map our own primary slot into page 2 (8000h-BFFFh) too - same ---
    ; --- as Stage1/Stage2's own INIT (see their own comment: the BIOS ---
    ; --- cartridge-boot sequence only auto-maps page 1).              ---
    IN A,(0A8h)
    LD B,A
    AND 0Ch
    ADD A,A
    ADD A,A
    LD C,A
    LD A,B
    AND 0CFh
    OR C
    OUT (0A8h),A

    DI
    ; (2026-09-07、実機フィードバック対応"Mission1でゲームオーバー処理の
    ; あとタイトルに遷移しない"): このINITはStage1/Stage2の"タイトルへ
    ; 戻る"トランポリン(GAME_OVER_SEQ==3/ENDING_ACT==4)の着地先としても
    ; 使われる冷起動と共通のエントリポイントだが、その場合HTIMI_HOOKは
    ; 送り手側(Stage1/Stage2)自身のBGM_TICKアドレスを指したまま残って
    ; いる(送り手側がDIしてから2ホップで飛んでくるので新規の割り込みは
    ; 発生しないはずだが、そのアドレスはこのバンク[title]がwindow Aに
    ; マップされた今、もう存在しない/無関係なコードを指している)。この
    ; ファイル自身のINIT_BGM(下記CALL)は「タイトル画面自身はBGM再生
    ; しない」設計のためHTIMI_HOOKを意図的に一切書き換えない(自身の
    ; コメント参照) - つまりこの古いフックは、次にEIされるまで誰も
    ; 上書きしないまま残り続ける。CALL INIGRP(SCREEN2初期化BIOS)は
    ; round53で発見したCALL INIT32(SCREEN1初期化BIOS)と同型のBIOS
    ; ルーチンであり、実機では内部でEI+HALT+DIによるvblank待ちを行う
    ; 可能性がある(z80emu.pyはこの内部動作を一切再現しないため検出
    ; 不可能)。そこがまさに、上記の古いフックがまだ生きたまま初めて
    ; 割り込みを受け付けてしまいうる箇所 - 冷起動時はBIOSデフォルトの
    ; 安全なbare RETのはずなので実害が出にくいが、この2つのトランポリン
    ; 経由の再入時だけ実害が出る非対称なバグだったと考えられる。この
    ; INITへ入る全経路(冷起動・トランポリン再入とも)に共通して安全な
    ; よう、CALL INIGRPより前に明示的にbare RETへリセットしておく
    ; (WAIT_FOR_STARTが送り手側で既に行っている同種の防御策と対になる、
    ; 受け手側での防御)。
    LD A,0C9h
    LD (HTIMI_HOOK),A
    CALL INIGRP

    ; 16x16 sprites + VDP interrupt enable - same R1 value Stage1/Stage2
    ; use (0E2h: 16K VRAM, display on, IE on, 16x16 sprite size). M1/M2
    ; (bits4/3, both 0 here) match SCREEN2's own mode requirement, so
    ; this is safe to write unconditionally after INIGRP already set R0's
    ; own mode bit.
    LD B,0E2h : LD C,1 : CALL WRTVDP

    ; border/backdrop black
    LD B,01h : LD C,7 : CALL WRTVDP

    ; install the RAM trampoline (own copy - see BANKSWITCH_TRAMPOLINE_RAM's comment)
    LD HL,BANKSWITCH_TRAMPOLINE_SRC
    LD DE,BANKSWITCH_TRAMPOLINE_RAM
    LD BC,BANKSWITCH_TRAMPOLINE_LEN
    LDIR

    ; mute all 3 PSG channels' volumes (defensive - nothing has played
    ; yet, but matches the "always leave the PSG in a known state"
    ; convention every INIT in this project already follows - same 3
    ; writes as build_full_rom.py's own pre-switch mute).
    LD A,8 : OUT (PSG_ADDR),A : XOR A : OUT (PSG_DATA),A
    LD A,9 : OUT (PSG_ADDR),A : XOR A : OUT (PSG_DATA),A
    LD A,10 : OUT (PSG_ADDR),A : XOR A : OUT (PSG_DATA),A

    ; ---------- BGM (round40, "タイトル含めて各ステージにドライバを配置し
    ; RAMにコピーしてステージスタート") ----------
    ; ここまで一切windowB(8000h-BFFFh)の内容を読んでいない(直前のPSG
    ; mute writeはVDP/PSGポートのみ)ので、bgm-dataバンクへの一時切替は
    ; 退避不要 - コピー後にこのファイル自身のbank1(標準ビルド=1、Comb=
    ; build_full_rom.py側のパッチで実際は変わらず1のまま、titleはComb
    ; でもbank0/1のまま)へ明示的に復帰してから続行する。
    CALL INIT_BGM

    ; ---------- title background art (SC2, RLE-compressed) ----------
    ; VRAM 0000h-37FFh(パターンジェネレータ+ネームテーブル/スプライト
    ; 属性/隙間+カラーテーブル)を丸ごと1本のストリームとして展開する
    ; ため、CALL 1回で完結する。
    CALL DECOMPRESS_TITLE_BG

    ; 展開したVRAM 1B00h-1B7Fh(スプライト属性テーブル)は元のSC2
    ; ダンプの生バイトをそのまま含んでいる(アート制作ツールがスプライト
    ; を意図的に使っていない保証は無い)ため、先頭エントリのYへ停止
    ; マーカー(0D1h)を明示的に上書きし、この画面ではスプライトを一切
    ; 表示しないことを保証する(このタイトル画面自体はスプライト
    ; パターンデータを持たない=SPRPAT以降が未定義のため、うっかり
    ; 何か表示されると内容不明のゴミになる)。
    LD A,0D1h : LD HL,SPRATR : CALL WRTVRM

    EI

; idle until the trigger button is pressed, then trampoline into
; Stage1 (bank2/3) - same 2-hop RAM-trampoline mechanism build_full_
; rom.py's own MAINLOOP_PATCH already uses for Stage1->Stage2.
; (2026-09-07、"タイトル画面でAボタンスタートならゲームオーバーあり、
; Bボタンならゲームオーバー無しに"): トリガー1(ボタンA)を優先チェック
; し、押されていればGAMEOVER_ENABLED=1でスタート。押されていなければ
; トリガー3(ボタンB、src/CYBER SHMUP.asmのREAD_INPUTと同じGTTRIG
; id規約 - id=1がトリガーA、id=3がトリガーB。id=0はどちらの規約にも
; 該当せず常に「押されていない」扱いになるため、当初id=0を使っていた
; のはBボタンが反応しない実機バグの直接原因だった)をチェックし、
; 押されていればGAMEOVER_ENABLED=0でスタート("これはテスト用なので
; BはあとAと同様にゲームオーバー有りにする" - 現時点では明示的にBだけ
; 0にする)。どちらも押されていなければ待機継続。
; (2026-09-13、"デバウンス処理をタイトル画面にも実装 今は押されたまま
; でも入力と判定してるんで なのでそうであったら一度ボタン押下が解除
; されるまでは入力としないように"): このINITはStage1/Stage2/GAME_OVER
; バンクからの「タイトルへ戻る」トランポリンの着地先としても使われる
; 共通エントリポイント(round60参照)のため、前の画面でボタンを押した
; ままここへ来た場合、そのまま即座に新規入力として誤検出してしまう
; 実害があった。両トリガー(GTTRIG id=1/3)が一度も揃って「離されている」
; 状態を観測するまでは先へ進まないブロッキング待ちを、実際の入力
; ポーリングループ(WAIT_FOR_START、ラベル名・意味とも既存のまま)より
; 前に挿入する。冷起動時は両トリガーとも最初から離れているため、この
; デバウンス自体は素通り(実質無コスト)でWAIT_FOR_STARTへ到達する -
; SCREEN3スライドショー中のSC3_CHECK_SKIPと全く同じ考え方。
WFS_DEBOUNCE:
    LD A,1 : CALL GTTRIG
    OR A
    JR NZ,WFS_DEBOUNCE
    LD A,3 : CALL GTTRIG
    OR A
    JR NZ,WFS_DEBOUNCE
WAIT_FOR_START:
    LD A,1
    CALL GTTRIG
    OR A
    JR NZ,WFS_BUTTON_A
    LD A,3
    CALL GTTRIG
    OR A
    JR Z,WAIT_FOR_START
    XOR A : LD (GAMEOVER_ENABLED),A
    JR WFS_PROCEED
WFS_BUTTON_A:
    LD A,1 : LD (GAMEOVER_ENABLED),A
WFS_PROCEED:

    ; (2026-09-07、"タイトル画面でボタン押下でサウンド追加"→2026-09-12、
    ; "スタートのサウンドと枠の演出は削除 ボタンを押したら即アニメへ
    ; 変わりにスタートのサウンドと枠の色の演出を このアニメの間ループ"):
    ; 旧来のボタン押下時の単発CALL PLAY_CONFIRM_BEEPはここでは呼ばない -
    ; ボタンを押したら即座にSCREEN3スライドショーへ入り、確認音+枠色
    ; フラッシュ演出(PLAY_CONFIRM_BEEP自体)はRUN_SCREEN3_SLIDESHOW内部で
    ; アニメーション全体の間ループし続ける(下記参照)。チャンネルB/PSG
    ; R7に関する経緯([Stage1へのバンク切替トランポリンより前、この
    ; ファイル自身の時間軸内で完結させる]等)は無変更のままPLAY_CONFIRM_
    ; BEEP自身のコメントを参照。
    ; (2026-09-12、"タイトル表示からMission 1表示の間に差し込んで
    ; 10回ループでMission 1表示に"): SCREEN3画像スライドショーを
    ; ここに挟む(6枚×10周+3枚の締めアニメ)。終わったら以下は無変更の
    ; ままStage1へトランポリン - Stage1自身が起動直後にCALL INIT32で
    ; SCREEN1へ戻すため、ここでSCREEN2に戻す必要はない。
    CALL RUN_SCREEN3_SLIDESHOW

    ; 実機フィードバック対応("バンク切り替えに失敗してる タイトルで
    ; ボタンを押すとフリーズ"): ここまでは割り込み許可(EI済み、BGM_TICK
    ; がH.TIMI経由で毎垂直帰線ごとに発火し続けている)状態。hop1でwindow
    ; B、hop2でwindow Aを切り替えてStage1自身のINITへ着地するが、hop2
    ; 完了の瞬間からStage1自身が(build_full_rom.py側のINIT_PATCHも含む)
    ; 自前のDIを実行するまでの間、この2ホップ+着地直後の複数命令は
    ; 割り込み許可のまま実行される - この間にH.TIMIが1回でも発火すると、
    ; 古いフック(このファイル自身のBGM_TICKアドレスを指したまま)が、
    ; その時点で既にStage1自身のコードに切り替わっているwindow Aの
    ; 中身を命令として誤実行してしまう(未定義動作、フリーズの直接
    ; 原因になり得る)。Stage2切替時にStage2自身のINIT冒頭へDIを追加した
    ; のと対になる修正として、ジャンプする送り手側であるここで先に
    ; DIしておくことで、hop1/hop2実行中も含め完全にこの競合を閉じる
    ; (受け手側のDIが実際に実行されるまでにどれだけ命令があっても、
    ; 割り込み自体がもう発火しないため無関係になる)。
    ; 実機フィードバック対応その3("実機、WebMSX、BlueMSX全てでタイトルで
    ; ボタン押下後フリーズ"、"起動ロゴは出ないがタイトルはクリアされて
    ; フリーズ"、続けて"ボタン押すって事はBIOS経由してるんで サウンド
    ; ドライバが破壊されてるかもな"): 上記のDIで新規の割り込みは止まる
    ; はずだが、それでも3プラットフォーム全てで再現する以上、DIより前の
    ; 何か(GTTRIG自体のBIOS内部処理、またはこのDI/JPの間に入り込む
    ; 何らかの経路)がH.TIMIを経由してこのファイル自身のBGM_TICKを
    ; 予期せず実行し、それが多重実行や中断でこのファイル自身のBGM状態
    ; (BGM_B/C_PTR等)を壊している可能性を切り分けるため、DIの直前で
    ; H.TIMIフックを明示的にbare RET(BIOSデフォルト、旧Stage1にあった
    ; 遺物と同じ形だが、ここでは意図的・一度きりの防御目的)へ戻す。
    ; これでDIより前に万一割り込みが発火しても実害の無いRETで終わり、
    ; Stage1自身のCALL INIT_BGMが改めて正しいフックを設置するまで安全。
    LD A,0C9h
    LD (HTIMI_HOOK),A
    DI

    LD A,STAGE1_BANK_B
    LD DE,7000h
    LD HL,GOTO_STAGE1_HOP2
    JP BANKSWITCH_TRAMPOLINE_RAM
GOTO_STAGE1_HOP2:
    LD A,STAGE1_BANK_A
    LD DE,6000h
    LD HL,STAGE1_INIT
    JP BANKSWITCH_TRAMPOLINE_RAM

BANKSWITCH_TRAMPOLINE_SRC:
    LD (DE),A
    JP (HL)
BANKSWITCH_TRAMPOLINE_LEN EQU $ - BANKSWITCH_TRAMPOLINE_SRC

; (2026-09-07、Round69 follow-up、"タイトル音はそれで良い ただし
; オクターブ下げてデューティ比50%で") ユーザーがWeb Audio試聴ツール
; 「Warning Beep Bench」で選定したv3候補("Rising alert chirp"→
; "Descending buzzer"の2候補をそのまま繋げてオクターブ下げ、2回再生)を
; そのまま実機PSGへ実装。旧版(round63、単純な単一トーン12ステップ
; 直線減衰)を全面置き換え。
;
; データ駆動(CONFIRM_STEPS、5byte/行×53行): 各行=(周期fine,周期coarse,
; 音量,半区間ウェイトlo,半区間ウェイトhi)。内訳: チャープ上昇スイープ
; 10行(周期520→180、Web版sweep(260,90,...)の全周期を2倍=オクターブ
; 下げ)+ホールド1行(周期180)+チャープfadeout14行(周期180、音量14→1)
; +ブザー下降スイープ14行(周期140→440、Web版sweep(70,220,...)の2倍)+
; ブザーfadeout14行(周期440、音量14→1)。ウェイト定数は既存の
; PCB_DELAY方式(1ループ=DEC DE+LD A,D+OR E+JR NZ=26T-state、
; MISSION_DELAY_3SEC等と同じ「Z80クロック直接カウント」の考え方)を
; 踏襲、Web版の各ステップのms値をN=ms*3579.545/26で換算。
;
; デューティ比50%の実装: 「そのままの塊で音量を書いて待つ」単一区間を
; 半分ずつの2区間に分割し、前半だけ実音量を書き、後半は明示的に音量0を
; 書く(PCB_ROW_ON_WAIT/PCB_ROW_OFF_WAIT) - 1行あたりの実質的な発音時間が
; 常にちょうど半分になる、Round43のBGMソフトウェアデューティ(位相
; カウンタ+ANDマスク)と同じ「音の長さの半分だけ鳴らす」考え方を、
; tick駆動ではなくこの短いSFX自身の同期busy-waitループの中で再現した
; もの。R2/R3(チャンネルBトーン周期)・R9(チャンネルB音量)を操作する
; ことに加え、VDP R7(ボーダー/バックドロップ色レジスタ)も行ごとに
; BORDER_TABLE(53byte、CONFIRM_STEPSと1:1対応)から読んだ値へ書き換える
; (Round69 follow-up、"Warning Beep Bench"のcandidate06自身が最初から
; 音+枠色フラッシュの対で設計されていたのに、PSG部分だけ実装して枠色
; 側を実装し忘れていた抜け - 「タイトルでボタンを押した時の確認音」に
; 対して実機で"枠描画はどこいったんだよ"と指摘され判明)。53行かけて
; REDGRAD=[黒1,暗赤6,中赤8,明赤9,中赤8,暗赤6,黒1]を滑らかに1往復
; (ビルド時にPython側で`REDGRAD[row*7//53]`を計算しDB literalへ焼き
; 込み、Z80側は除算不要)、53行×2回再生と対応して枠も2回明滅する。
; チャンネルB自体は元々INIT_BGMが常時トーン有効のまま用意している
; 遊休チャンネル。Trashes: AF,BC,DE,HL,IX。
CONFIRM_STEP_COUNT EQU 53
CONFIRM_GAP_DELAY  EQU 15150

PLAY_CONFIRM_BEEP:
    CALL PCB_PLAY_TABLE
    LD DE,CONFIRM_GAP_DELAY
PCB_GAP_WAIT:
    DEC DE
    LD A,D : OR E
    JR NZ,PCB_GAP_WAIT
    CALL PCB_PLAY_TABLE
    RET

PCB_PLAY_TABLE:
    LD HL,CONFIRM_STEPS
    LD IX,BORDER_TABLE
    LD B,CONFIRM_STEP_COUNT
PCB_ROW_LOOP:
    PUSH BC
    CALL PCB_PLAY_ONE_ROW
    POP BC
    INC IX
    DJNZ PCB_ROW_LOOP
    RET

; HLが指す5byte行を1行分再生し、HLを+5だけ進めて戻る(IXの1バイト
; 分の前進[(IX+0)=このコマの枠色]は呼び出し元PCB_ROW_LOOPが担当)。
; 行フォーマット: (周期fine,周期coarse,音量,半区間ウェイトlo,ウェイトhi)
PCB_PLAY_ONE_ROW:
    DI
    LD A,2 : OUT (PSG_ADDR),A
    LD A,(HL) : OUT (PSG_DATA),A   ; ch B tone period fine
    INC HL
    LD A,3 : OUT (PSG_ADDR),A
    LD A,(HL) : OUT (PSG_DATA),A   ; ch B tone period coarse
    INC HL
    LD A,9 : OUT (PSG_ADDR),A
    LD A,(HL) : OUT (PSG_DATA),A   ; ch B volume (duty ON half)
    INC HL
    LD A,(IX+0) : OUT (99h),A
    NOP
    NOP
    LD A,87h : OUT (99h),A         ; reg7|80h = VDP R7 (border/backdrop color)
    NOP
    NOP
    EI
    LD E,(HL) : INC HL
    LD D,(HL) : INC HL
    PUSH DE
PCB_ROW_ON_WAIT:
    DEC DE
    LD A,D : OR E
    JR NZ,PCB_ROW_ON_WAIT
    DI
    LD A,9 : OUT (PSG_ADDR),A : XOR A : OUT (PSG_DATA),A  ; duty OFF half (silence)
    EI
    POP DE
PCB_ROW_OFF_WAIT:
    DEC DE
    LD A,D : OR E
    JR NZ,PCB_ROW_OFF_WAIT
    RET

; (2026-09-12、実機フィードバック"画面真っ赤だが スクリーン3は枠使え
; ないのか"): SCREEN3(Multicolor)モード中にPLAY_CONFIRM_BEEPの枠色
; フラッシュ(VDP R7書き込み)を行うと画面全体が赤一色になる実機不具合が
; 判明した(この演出自体はGraphics1/SCREEN2[タイトル背景]モードでの
; ボタン押下時は実機確認済みだったが、Multicolorモードとの組み合わせは
; 今回が初めての実機テストだった)。根本原因の特定は保留し、SCREEN3
; スライドショー中は枠色フラッシュを完全に省略する方針にした。
; (2026-09-12、実機フィードバック"表示は出来た だが音2回鳴らして
; 1コマじゃねえんだよ 音は割り込みで鳴らしてんだろうが 鳴らしながら
; アニメするんだよ"): 当初はここに枠色フラッシュ無しのPLAY_CONFIRM_
; BEEP_NO_BORDER(PCB_PLAY_TABLE_NB/PCB_PLAY_ONE_ROW_NB、画像の
; 切り替わりごとに毎回ブロッキング呼び出しするbusy-wait版)を実装したが、
; 「1コマに確認音が2回鳴る」「画像切り替えが確認音の再生時間に
; 引きずられて遅くなる」という指摘を受け全面撤回。combined_test.asmの
; BGM_TICKと同じ設計のH.TIMI駆動バックグラウンドループ(下記
; SC3_CONFIRM_TICK)へ置き換えたため、この3ルーチン(busy-wait版)は
; 完全に不要になり削除した。

; REDGRAD=[1,6,8,9,8,6,1](黒/暗赤/中赤/明赤/中赤/暗赤/黒)を53行に
; row*7//53で滑らかに配分(Pythonで事前計算、floor除算なので毎回
; 7-8行ずつ同じ値が続く形になる)。CONFIRM_STEPSと同じ53要素、
; 添字も1:1で対応。
BORDER_TABLE:
    DB 1,1,1,1,1,1,1,1
    DB 6,6,6,6,6,6,6,6
    DB 8,8,8,8,8,8,8
    DB 9,9,9,9,9,9,9,9
    DB 8,8,8,8,8,8,8
    DB 6,6,6,6,6,6,6,6
    DB 1,1,1,1,1,1,1

; --- チャープ上昇スイープ(周期520->180、10行、オクターブ下げ済み) ---
CONFIRM_STEPS:
    DB   8,2,14,108,2
    DB 226,1,14,108,2
    DB 188,1,14,108,2
    DB 151,1,14,108,2
    DB 113,1,14,108,2
    DB  75,1,14,108,2
    DB  37,1,14,108,2
    DB   0,1,14,108,2
    DB 218,0,14,108,2
    DB 180,0,14,108,2
; --- ホールド(周期180、1行) ---
    DB 180,0,14, 34,16
; --- チャープfadeout(周期180、音量14->1、14行) ---
    DB 180,0,14, 57,3
    DB 180,0,13, 57,3
    DB 180,0,12, 57,3
    DB 180,0,11, 57,3
    DB 180,0,10, 57,3
    DB 180,0, 9, 57,3
    DB 180,0, 8, 57,3
    DB 180,0, 7, 57,3
    DB 180,0, 6, 57,3
    DB 180,0, 5, 57,3
    DB 180,0, 4, 57,3
    DB 180,0, 3, 57,3
    DB 180,0, 2, 57,3
    DB 180,0, 1, 57,3
; --- ブザー下降スイープ(周期140->440、14行、オクターブ下げ済み) ---
    DB 140,0,14,217,3
    DB 163,0,14,217,3
    DB 186,0,14,217,3
    DB 209,0,14,217,3
    DB 232,0,14,217,3
    DB 255,0,14,217,3
    DB  22,1,14,217,3
    DB  46,1,14,217,3
    DB  69,1,14,217,3
    DB  92,1,14,217,3
    DB 115,1,14,217,3
    DB 138,1,14,217,3
    DB 161,1,14,217,3
    DB 184,1,14,217,3
; --- ブザーfadeout(周期440、音量14->1、14行) ---
    DB 184,1,14, 57,3
    DB 184,1,13, 57,3
    DB 184,1,12, 57,3
    DB 184,1,11, 57,3
    DB 184,1,10, 57,3
    DB 184,1, 9, 57,3
    DB 184,1, 8, 57,3
    DB 184,1, 7, 57,3
    DB 184,1, 6, 57,3
    DB 184,1, 5, 57,3
    DB 184,1, 4, 57,3
    DB 184,1, 3, 57,3
    DB 184,1, 2, 57,3
    DB 184,1, 1, 57,3

; ---------- title background decompressor (round43) ----------
; 自前の対称RLE(制御バイトbit7=0:リテラル/1:反復、下位7bitは長さ-1、
; 詳細はtools/title_screen/title_bg_gen.pyの長いコメント参照)を、VRAM
; 0000hから始まるVDPのオートインクリメント書き込みへ直接ストリーム
; 展開する。展開先アドレスを個別に管理する必要が無いのが利点 - VDPの
; アドレスレジスタへ一度だけ0000h+書き込みモードを設定すれば、以後は
; ポート98hへ書くたびに自動的に次のアドレスへ進む(実機・BIOS標準の
; 挙動)。
;
; セグメント数(TITLE_BG_RLE_SEGMENTS、Python側で生成時に確定する定数)
; を16bitのdown-counterとして使い、1セグメント処理するたびにDEを
; 1減算してゼロになったら終了 - 圧縮ストリーム自体に終端マーカーを
; 持たせない設計(セグメント数の方を信頼できる唯一の終端条件にする
; ことで、ストリームの読み過ぎ/読み足りなさが起きても即座に検出できる
; ようにするため、というほど厳密な意図ではなく、単に「制御バイト+
; データの組が何個あるか」を素直にdown-counterにしただけ)。
DECOMPRESS_TITLE_BG:
    XOR A : OUT (VDP_ADDR),A
    LD A,40h : OUT (VDP_ADDR),A     ; VRAM書き込みアドレス=0000h、以後オートインクリメント
    LD HL,TITLE_BG_RLE
    LD DE,TITLE_BG_RLE_SEGMENTS
DTB_LOOP:
    LD A,(HL) : INC HL
    OR A
    JP M,DTB_RUN                    ; bit7=1(符号ビット) -> 反復セグメント
    AND 7Fh
    INC A
    LD B,A
; 実機フィードバック対応("実機ではグリッチ状態 TMS9918のスクリーン2に
; 設定されてるか確認"): openMSX(C-BIOS_MSX1)での実バイト単位トレース
; 調査により、原因はスクリーン2設定ではなくこの直下(旧OTIR使用箇所)の
; リテラルセグメント転送だったと特定。OTIRはこのアセンブラ・エミュレータ
; 環境(z80emu.py)では正しく動作するが、実機のVDPデータポート(98h)へ
; ブロック転送する用途ではバスタイミングがVDPの要求と合わず信頼できない
; というMSXでよく知られたハードウェア制約に該当し(z80emu.pyはこの制約を
; 一切再現しない)、実機では書き込みが実質無効化され後続の全セグメントが
; 累積的にズレて画面全体が乱れる形で顕在化した。反復セグメント側
; (下のDTB_RUN_LOOP、元々OTIRを使わずDJNZ+通常のOUTだった箇所)は
; 実機でも正しく動作していたため、リテラル側もOTIRをやめて同じ
; DJNZ+通常OUTの手動ループへ統一して解消。
DTB_LIT_LOOP:
    LD A,(HL) : INC HL
    OUT (VDP_DATA),A
    DJNZ DTB_LIT_LOOP
    JR DTB_NEXT
DTB_RUN:
    AND 7Fh
    INC A
    LD B,A
    LD A,(HL) : INC HL
DTB_RUN_LOOP:
    OUT (VDP_DATA),A
    DJNZ DTB_RUN_LOOP
DTB_NEXT:
    DEC DE
    LD A,D : OR E
    JR NZ,DTB_LOOP
    RET

; ---------- BGM driver (Round40) ----------
; tools/stage2_combined/combined_test.asmの同名ドライバと同型(chB/chC
; 独立ポインタ・タイマー、詳細な設計理由はそちらの長いコメント参照)。
; このファイルは他に一切PSGを使わない(自機/敵/SFXが存在しない)ため、
; Stage2と違いR7の毎tick read-modify-writeは不要 - R7は下のINIT_BGM内で
; 一度だけ0B1h(tone B/C enable、Stage1が実際に使っている値と同一 -
; GTTRIGが依存するportA/B方向ビットを含め安全な値と分かっている)を書く。
; 曲はALONE_FIGHTER("Alone_Fighter.mid")、トランポリンでStage1へ移動した
; 後もStage1側は同じ曲をこのファイルがコピーしたRAMからそのまま読む
; (src/CYBER SHMUP.asm自身のBGM_TICKコメント参照 - Stage1はPSGチャンネル
; B/Cを既存SFXと共有しているため自分ではバンク切替もRAMコピーもしない)。
HTIMI_HOOK      EQU 0FD9Fh
BGM_NOTE_REST   EQU 0FFh
BGM_LOOP_MARK   EQU 0FEh
; (2026-09-06、TryZ/GFEnding追加でNUM_NOTES35→60へ拡張、周期テーブルが
; 伸びた分だけ以下のRAMオフセットが後方へシフト - tools/bgm_data/
; bgm_bank_gen.pyの`python3 bgm_bank_gen.py`出力値と一致させること)
BGM_PERIOD_LO_RAM EQU 0C000h
BGM_PERIOD_HI_RAM EQU 0C03Ch
BGM_B_BASE        EQU 0C078h    ; ALONE_FIGHTER track0(chB)先頭
BGM_C_BASE        EQU 0C267h    ; ALONE_FIGHTER track1(chC)先頭
; (2026-09-06、CONTROL_OFFSET拡張0x800→0x900に伴い0xC800→0xC900へ
; シフト - bgm_bank_gen.pyのCONTROL_OFFSET自身のコメント[自己発見RAM
; 衝突バグの経緯]参照)
BGM_B_PTR   EQU 0C900h
BGM_C_PTR   EQU 0C902h
BGM_B_TIMER EQU 0C904h
BGM_C_TIMER EQU 0C905h
BGM_B_REST  EQU 0C906h
BGM_C_REST  EQU 0C907h

; 実機フィードバック対応その3("BGMが1chしかなってないと言うか 恐らく
; エンベロープの影響で発音できてないな HWエンベロープはコントロール
; 不能と判断 ソフトに切り替える...試聴ツールで決める これなら
; デューティ比にも対応できるからな"): 完全にソフトウェア側でエンベロープ
; を実現する方式に切り替え(詳細な設計理由・番兵エントリの扱いは
; combined_test.asmの同名定数の長いコメント参照)。試聴ツール(PSG BGM
; Bench)でユーザーが選定: **パート1(chB)=BELL形状+デューティ比50%、
; パート2(chC)=LINEAR形状+デューティOFF**。
BGM_ENV_LAST_INDEX EQU 15
BGM_B_DUTY_MASK    EQU 1
; 実機フィードバック"BGM音量を下げたいが現在は最大か?"→"中程度下げる
; (-4、ピーク11)": R9/R10へ書く直前に一律で減算(0未満はクランプ)。
BGM_VOL_ATTEN      EQU 4
BGM_B_ENV_LEVEL  EQU 0C908h
BGM_B_ENV_IDX    EQU 0C909h
BGM_B_ENV_CD     EQU 0C90Ah
BGM_B_DUTY_PHASE EQU 0C90Bh
BGM_C_ENV_LEVEL  EQU 0C90Ch
BGM_C_ENV_IDX    EQU 0C90Dh
BGM_C_ENV_CD     EQU 0C90Eh

BGM_ENV_BELL_TABLE:
    DB 15,3,14,4,13,5,12,6,11,6,10,6,9,7,8,9,7,9,6,11,5,13,4,16,3,22,2,33,1,71,0,0
BGM_ENV_LINEAR_TABLE:
    DB 15,2,14,3,13,2,12,3,11,2,10,3,9,3,8,3,7,2,6,3,5,3,4,2,3,3,2,2,1,3,0,0

; 実機フィードバック対応("ステージ1ボスもBGMをTryZに"): Stage1は自前の
; バンク切替を一切行わない設計を維持するため(src/CYBER SHMUP.asmの
; BGM_TRYZ_CHB/CHC_BASE自身のコメント参照)、TryZの生データもここで
; ALONE_FIGHTERと同様に一度だけRAMへコピーしておく。chB(741byte)+
; chC(73byte)はbgm-dataバンク内で連続しているため1回のLDIRで両方
; 転送できる(コピー先0xC910+741=0xCBF5にchCが自動的に来る - src/
; CYBER SHMUP.asmのBGM_TRYZ_CHC_BASEと一致させること)。
; (2026-09-08、"ではゲームオーバーBGM...これで組み込んでくれ"): 同じ
; 理由でGAME_OVERジングル(chB35byte+chC15byte)もここでコピー。src/
; CYBER SHMUP.asmのBGM_GAMEOVER_CHB/CHC_BASEと一致させること。
; (round135follow-up16、"ボスを別バンクに移してくれ だいぶ削減出来る
; はずだ"): 同じ理由でStage1ボス本体グラフィック(BOSS_PATTERNS、
; 512byte)もここでコピー。src/CYBER SHMUP.asmのBOSS_PATTERNSと
; 一致させること。
; (2026-09-14、"キャラデータはかなり圧縮ができる筈 RLEで十分だろう"):
; BOSS_PATTERNSはRLE圧縮済み(512byte->290byte)、コピー量もそのぶん
; 減った。Stage1自身はもう生バイト列ではなく圧縮バイト列をコピー先
; RAMにそのまま受け取り、BOSS_SPAWNの瞬間にVRAMへ展開する
; (DECOMPRESS_RLE_TO_VRAM、src/CYBER SHMUP.asm側)。tools/bgm_data/
; bgm_bank_gen.pyの`python3 bgm_bank_gen.py`出力(STAGE1_BOSS_CHARDATA
; エントリ)と一致させること。
INIT_BGM:
    LD A,2                       ; standalone bgm-dataバンク(Combでは6へパッチ)
    LD (7000h),A
    LD HL,08000h : LD DE,0C000h : LD BC,078h : LDIR   ; 周期テーブル(60note*2)
    LD HL,08078h : LD DE,0C078h : LD BC,0628h : LDIR  ; ALONE_FIGHTER chB+chC
    LD HL,08E32h : LD DE,0C910h : LD BC,032Eh : LDIR  ; TryZ chB+chC(Stage1ボス用)
    LD HL,0931Bh : LD DE,0CC42h : LD BC,010Dh : LDIR  ; StageClear chB+chC+chA(Stage1ステージクリア用)
    LD HL,09428h : LD DE,0CD5Bh : LD BC,032h : LDIR   ; GAME_OVER chB+chC(Stage1ゲームオーバー用)
    LD HL,0BD0Ah : LD DE,0CD8Dh : LD BC,0122h : LDIR  ; BOSS_PATTERNS(Stage1ボス本体グラフィック用、RLE圧縮済み290byte)
    LD HL,0BE2Ch : LD DE,0D0C0h : LD BC,0E3h : LDIR   ; EBUZ2_MK2_CHARDATA(round136、Ebuz Mk2の行形状データ+シーケンステーブル、227byte、無圧縮)
    LD HL,0BF0Fh : LD DE,0D20Ah : LD BC,048h : LDIR   ; STAGE1_BOSS_MISC_PATTERNS(round145、BOSS_HEX/ORBIT/DFL_BULLET/EXPLOSION統合、RLE圧縮済み72byte)
    LD HL,0BF57h : LD DE,0D28Ah : LD BC,072h : LDIR   ; STAGE1_MISSION_GAMEOVER_FONT(round145、MISSION/GAMEOVERフォント統合、RLE圧縮済み114byte)
    LD A,1                       ; このファイル自身のbank1(Comb/standaloneとも1のまま)
    LD (7000h),A

    LD HL,BGM_B_BASE
    LD (BGM_B_PTR),HL
    XOR A
    LD (BGM_B_TIMER),A
    LD (BGM_B_REST),A
    LD (BGM_B_ENV_LEVEL),A
    LD (BGM_B_ENV_IDX),A
    LD (BGM_B_ENV_CD),A
    LD (BGM_B_DUTY_PHASE),A
    LD HL,BGM_C_BASE
    LD (BGM_C_PTR),HL
    LD (BGM_C_TIMER),A
    LD (BGM_C_REST),A
    LD (BGM_C_ENV_LEVEL),A
    LD (BGM_C_ENV_IDX),A
    LD (BGM_C_ENV_CD),A

    LD A,7 : OUT (PSG_ADDR),A
    LD A,0B1h : OUT (PSG_DATA),A  ; tone B/C enable, tone A + noise B/C disable, portA=in/portB=out

    ; ユーザー指示("タイトルBGMも停止 まともになるまでCombのみで"):
    ; Stage1側の音楽再生(RAM上のALONE_FIGHTER周期テーブル+曲データ)は
    ; 上のLDIRで既にコピー済みのため無変更(Stage1のCALL INIT_BGMが
    ; 起動時にそのRAMを読むだけ、というStage1側の既存設計を維持)。ここで
    ; 意図的にスキップしているのはHTIMI_HOOKの設置(=このファイル自身の
    ; BGM_TICKをH.TIMI経由で毎VBlank起動する部分)だけ - これによりタイトル
    ; 画面自身は音楽を全く再生しない(HTIMI_HOOKは実機BIOSのデフォルトの
    ; ままRET、このファイルは一度も書き換えない)。BGM_TICK自身のコードは
    ; 削除せず残す(将来再度有効化する可能性に備え、title_test.pyの既存
    ; テストも引き続きBGM_TICKを直接CALLして検証可能)。
    RET

BGM_TICK:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL
    CALL BGMT_UPDATE_B
    CALL BGMT_UPDATE_C
    POP HL
    POP DE
    POP BC
    POP AF
    RET

; chB=BELL形状+デューティ50%。継続tickも毎回テーブルを1段進めてR9へ
; 書く(HWエンベロープと違い共有ジェネレータの制約が無いため、休符
; 以外は常にPSGへ書いてよい)。
BGMT_UPDATE_B:
    LD A,(BGM_B_TIMER)
    OR A
    JR Z,BGMT_UB_NEWROW
    DEC A
    LD (BGM_B_TIMER),A
    JR BGMT_UB_ENV_STEP
BGMT_UB_NEWROW:
    LD HL,(BGM_B_PTR)
    LD A,(HL)
    CP BGM_LOOP_MARK
    JR NZ,BGMT_UB_GOT
    LD HL,BGM_B_BASE
    LD A,(HL)
BGMT_UB_GOT:
    LD C,A
    INC HL
    LD A,(HL)
    INC HL
    LD (BGM_B_PTR),HL
    ; round40 実機フィードバック対応: off-by-one修正(combined_test.asm
    ; の同じ箇所の長いコメント参照) - 読み込みtick自体も1tick分の
    ; 再生になるため、DEC Aで合計durationぴったりに補正する。
    DEC A
    LD (BGM_B_TIMER),A
    LD A,C
    CP BGM_NOTE_REST
    JR Z,BGMT_UB_SETREST
    XOR A
    LD (BGM_B_REST),A
    LD E,C : LD D,0
    LD HL,BGM_PERIOD_LO_RAM : ADD HL,DE : LD A,(HL) : LD B,A
    LD HL,BGM_PERIOD_HI_RAM : ADD HL,DE : LD A,(HL) : LD C,A
    LD A,2 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A
    LD A,3 : OUT (PSG_ADDR),A
    LD A,C : OUT (PSG_DATA),A
    LD HL,BGM_ENV_BELL_TABLE
    LD A,(HL) : LD (BGM_B_ENV_LEVEL),A
    INC HL
    LD A,(HL) : DEC A : LD (BGM_B_ENV_CD),A
    XOR A : LD (BGM_B_ENV_IDX),A
    LD A,BGM_B_DUTY_MASK : LD (BGM_B_DUTY_PHASE),A
    JR BGMT_UB_ENV_WRITE
BGMT_UB_SETREST:
    LD A,1
    LD (BGM_B_REST),A
    LD A,9 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    RET
BGMT_UB_ENV_STEP:
    LD A,(BGM_B_REST)
    OR A
    RET NZ
    LD A,(BGM_B_ENV_CD)
    OR A
    JR Z,BGMT_UB_ENV_ADVANCE
    DEC A
    LD (BGM_B_ENV_CD),A
    JR BGMT_UB_ENV_WRITE
BGMT_UB_ENV_ADVANCE:
    LD A,(BGM_B_ENV_IDX)
    CP BGM_ENV_LAST_INDEX
    JR Z,BGMT_UB_ENV_WRITE
    INC A
    LD (BGM_B_ENV_IDX),A
    LD L,A : LD H,0
    ADD HL,HL
    LD DE,BGM_ENV_BELL_TABLE
    ADD HL,DE
    LD A,(HL) : LD (BGM_B_ENV_LEVEL),A
    INC HL
    LD A,(HL)
    OR A
    JR Z,BGMT_UB_ENV_WRITE
    DEC A
    LD (BGM_B_ENV_CD),A
BGMT_UB_ENV_WRITE:
    LD A,(BGM_B_DUTY_PHASE)
    INC A
    LD (BGM_B_DUTY_PHASE),A
    AND BGM_B_DUTY_MASK
    LD B,0
    JR NZ,BGMT_UB_ENV_OUT
    LD A,(BGM_B_ENV_LEVEL)
    SUB BGM_VOL_ATTEN
    JR NC,BGMT_UB_ATTEN_OK
    XOR A                            ; 減算でアンダーフローしたら0にクランプ
BGMT_UB_ATTEN_OK:
    LD B,A
BGMT_UB_ENV_OUT:
    LD A,9 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A
    RET

; chC=LINEAR形状+デューティOFF。構造はchBと同型だが、デューティ
; ゲートを持たず毎tick常にエンベロープ値をそのままR10へ書く。
BGMT_UPDATE_C:
    LD A,(BGM_C_TIMER)
    OR A
    JR Z,BGMT_UC_NEWROW
    DEC A
    LD (BGM_C_TIMER),A
    JR BGMT_UC_ENV_STEP
BGMT_UC_NEWROW:
    LD HL,(BGM_C_PTR)
    LD A,(HL)
    CP BGM_LOOP_MARK
    JR NZ,BGMT_UC_GOT
    LD HL,BGM_C_BASE
    LD A,(HL)
BGMT_UC_GOT:
    LD C,A
    INC HL
    LD A,(HL)
    INC HL
    LD (BGM_C_PTR),HL
    ; round40 実機フィードバック対応: BGMT_UB_NEWROWの同じoff-by-one
    ; 修正コメント参照。
    DEC A
    LD (BGM_C_TIMER),A
    LD A,C
    CP BGM_NOTE_REST
    JR Z,BGMT_UC_SETREST
    XOR A
    LD (BGM_C_REST),A
    LD E,C : LD D,0
    LD HL,BGM_PERIOD_LO_RAM : ADD HL,DE : LD A,(HL) : LD B,A
    LD HL,BGM_PERIOD_HI_RAM : ADD HL,DE : LD A,(HL) : LD C,A
    LD A,4 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A
    LD A,5 : OUT (PSG_ADDR),A
    LD A,C : OUT (PSG_DATA),A
    LD HL,BGM_ENV_LINEAR_TABLE
    LD A,(HL) : LD (BGM_C_ENV_LEVEL),A
    INC HL
    LD A,(HL) : DEC A : LD (BGM_C_ENV_CD),A
    XOR A : LD (BGM_C_ENV_IDX),A
    JR BGMT_UC_ENV_WRITE
BGMT_UC_SETREST:
    LD A,1
    LD (BGM_C_REST),A
    LD A,10 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    RET
BGMT_UC_ENV_STEP:
    LD A,(BGM_C_REST)
    OR A
    RET NZ
    LD A,(BGM_C_ENV_CD)
    OR A
    JR Z,BGMT_UC_ENV_ADVANCE
    DEC A
    LD (BGM_C_ENV_CD),A
    JR BGMT_UC_ENV_WRITE
BGMT_UC_ENV_ADVANCE:
    LD A,(BGM_C_ENV_IDX)
    CP BGM_ENV_LAST_INDEX
    JR Z,BGMT_UC_ENV_WRITE
    INC A
    LD (BGM_C_ENV_IDX),A
    LD L,A : LD H,0
    ADD HL,HL
    LD DE,BGM_ENV_LINEAR_TABLE
    ADD HL,DE
    LD A,(HL) : LD (BGM_C_ENV_LEVEL),A
    INC HL
    LD A,(HL)
    OR A
    JR Z,BGMT_UC_ENV_WRITE
    DEC A
    LD (BGM_C_ENV_CD),A
BGMT_UC_ENV_WRITE:
    LD A,10 : OUT (PSG_ADDR),A
    LD A,(BGM_C_ENV_LEVEL)
    SUB BGM_VOL_ATTEN
    JR NC,BGMT_UC_ATTEN_OK
    XOR A                            ; 減算でアンダーフローしたら0にクランプ
BGMT_UC_ATTEN_OK:
    OUT (PSG_DATA),A
    RET

; ===== SCREEN3(Multicolor)スライドショー(2026-09-12、"タイトルの
; バンクに 一旦タイトル表示からMission 1表示の間に差し込んで10回
; ループでMission 1表示に"、続けて"別に割り込みで同期取る必要は
; ないぞ 適当にNopループでいい3フレ分の"、続けて"ではさっきの6枚の
; 後に一枚目を0.5秒 これを4ループ その後に2枚目を1秒 3枚目を3秒表示
; スタートのサウンドと枠の演出は削除 ボタンを押したら即アニメへ
; 変わりにスタートのサウンドと枠の色の演出を このアニメの間ループ")。
; tools/screen3_test/screen3_test.asm(実機で"おｋ意図通り表示できた"
; 確認済みの独立テストツール)のXOR差分圧縮方式をそのまま移植 - PGT
; (パターンジェネレータ)はRAM上のSHADOW_PGTを経由してVRAMへ一括反映、
; 1枚目は通常のRLE圧縮でフル保持、以後は直前フレームとのXOR差分を
; RLE圧縮して保持(データはtools/screen3_test/screen3_gen.pyが生成)。
; ネームテーブルは6枚とも完全に同一のため1回だけVRAM 1800hへ書き込む。
;
; フレーム待ちは(ユーザー指示"割り込みで同期取る必要はない...Nopループ
; でいい")src/CYBER SHMUP.asmのMISSION_DELAY_3SEC等と同じ、割り込み/
; JIFFY系に一切依存しないZ80クロック直接カウントのbusy-waitのみで
; 実装する。3フレーム分(約50ms)はDE 16bitの単純デクリメントループ
; (CONFIRM_GAP_DELAY等と同じ26T-state/iteration)、0.5/1/3秒はDE単体
; では桁が足りない(16bit上限は約476ms分)ためMISSION_DELAY_3SEC同型の
; D×B×C三重ループ(D=10で実測約2.94秒という既存較正値をそのまま流用、
; 1秒=D3・0.5秒=D2で近似)を使う。
;
; "スタートのサウンドと枠の演出は削除...変わりに...このアニメの間
; ループ": 旧来のボタン押下時単発のPLAY_CONFIRM_BEEP呼び出しは撤去し、
; 代わりにこのスライドショー全体(6枚×1周+締めの3枚)を通じて確認音を
; 画像の切り替わりごとに繰り返し呼ぶことで、アニメーションの間ずっと
; 鳴り続けるように実装する(単一スレッドのbusy-wait設計のため、映像と
; 音を厳密に同期させることはできない - "適当でいい"というユーザー
; 方針に基づき、画像の切り替わりのたびに1回再生する形で十分とする)。
; (2026-09-12、実機フィードバック"画面真っ赤だが スクリーン3は枠使え
; ないのか"): SCREEN3モード中の枠色フラッシュが画面全体を赤一色に
; してしまう不具合が判明したため、枠色フラッシュ無しのPLAY_CONFIRM_
; BEEP_NO_BORDER(PSGトーンのみ)を使う。
; (2026-09-12、実機フィードバック"10ループなんて指定してないし"):
; メインループ回数を当初の10から1(1周のみ、繰り返し無し)へ訂正。
; (2026-09-12、実機フィードバック"音は出てるが画面真っ黒のまま 何も
; 表示されてない"): tools/screen3_test/screen3_test.asmの独立テスト
; ツールはCALL INIT32(SCREEN1)をベースにしていたため、R0のM3ビット
; (bit1)は元々0(Graphics1/Multicolor共通の値)のままで、R1にM2ビット
; (0EAh)を追加するだけでMulticolorモード(M1=0,M2=1,M3=0)へ正しく
; 切り替わっていた。しかしこのタイトルバンクの土台はCALL INIGRP
; (SCREEN2/Graphics2)であり、INIGRP自身がR0のM3ビットを1にセット
; している(139行目付近の既存コメント"this is safe to write
; unconditionally after INIGRP already set R0's own mode bit"参照)。
; RUN_SCREEN3_SLIDESHOWはR1しか書き換えていなかったため、実際には
; M1=0,M2=1,M3=1という本来のMulticolorとは異なるビット組み合わせに
; なっていた(TMS9918の未定義の組み合わせで、実機で画面が真っ黒に
; なる=音は鳴るがVDP表示だけ死ぬ、という報告内容と整合する)。
; R0を明示的に0(M3=0、Graphics1/Multicolor共通値)へ書き戻すことで
; 解消する。
; (2026-09-12、実機フィードバック"グリッチのまま変わってねえよ...
; ちゃんとスクリーン3に初期化しろ...レンダリングで確認しろ"): 上記の
; R0修正だけでは解消しなかったため、実際にopenMSX(headless、-control
; stdio外部制御)でPCをRUN_SCREEN3_SLIDESHOWへ直接ジャンプさせて
; 実行させ、`screenshot`コマンドで実際の描画結果をPNGとして確認した
; ところ、ユーザー報告と全く同じ縦縞グリッチを再現できた。続けて
; "VDP regs"デバッガブルで実際のVDPレジスタ値を直接読み取ったところ、
; **R4(パターンジェネレータテーブルのベースアドレスレジスタ)が
; INIGRPの設定値3のまま一度も書き換えられていなかった**と判明。
; R4=3の場合、パターンジェネレータテーブルのベースは3*0800h=1800h
; になる(Text/Graphics1/Multicolorでは2KB単位、R4の下位3bitで
; 16KB空間内の8ブロックから選択)- これはネームテーブル自身の
; ベースアドレス(R2=6→1800h)と全く同じ番地であり、VDPは自分自身が
; 書き込んだネームテーブルの単純なランプ値(0-191の機械的な連番)を
; パターンジェネレータデータとして誤読していた。これが実機で見えた
; 「規則正しいがおかしい」縦縞模様の正体(SHOW_SC3_IMG1がVRAM 0000h
; へ正しく書いたPGTデータは、VDPが実際に参照するアドレス[1800h]とは
; 全く別の場所だったため一切表示に反映されていなかった)。
; R4を明示的に0(パターンジェネレータテーブルを0000hへ、Graphics1/
; Multicolor共通の標準値)へ書き戻すことで解消する。
;
; (2026-09-12、実機フィードバック"表示は出来た だが音2回鳴らして
; 1コマじゃねえんだよ 音は割り込みで鳴らしてんだろうが 鳴らしながら
; アニメするんだよ"): 確認音はH.TIMI駆動のバックグラウンドループへ
; 変更(combined_test.asmのBGM_TICKと同じ設計)。SC3_CONFIRM_TICKを
; HTIMI_HOOKへ設置しSC3_CT_PTR/TIMER/ROWS_LEFTを初期化した後は、
; 画像の切り替わりループ(busy-wait、"適当にNopループでいい"の方針
; 通り無変更)を回すだけでよく、確認音はその間ずっと割り込みで自律的に
; 鳴り続け末尾(SC3_CONFIRM_TICK_ROW_COUNT行)まで行ったら自動的に
; 先頭へループする - 画像1枚ごとの明示的なCALLは不要になったため撤去。
;
; (2026-09-13、"ではボーダーカラーの点滅をサウンドと同期して 削除前の
; 実装と同じだ"): PLAY_CONFIRM_BEEP(タイトルボタン押下時の確認音)が
; 元々音と対で行っていたVDP R7(ボーダー/バックドロップ色)のBORDER_
; TABLE同期フラッシュを、このH.TIMI駆動版にも移植。**重要な既知の
; リスク**: このファイル自身のコメント(下記RUN_SCREEN3_SLIDESHOWの
; VDP R4修正の説明の直前、2026-09-12付け)に記録済みの通り、"画面
; 真っ赤だが スクリーン3は枠使えないのか"という実機フィードバックで
; 「SCREEN3(Multicolor)モード中にVDP R7書き込みを行うと画面全体が
; 赤一色になる実機不具合」が既に一度確認されており、根本原因の特定は
; 保留したまま「SCREEN3スライドショー中は枠色フラッシュを完全に
; 省略する」方針で回避していた経緯がある。今回はユーザーの明示指示
; により実装するが、この既知の不具合が再発する可能性は排除できて
; いない(実機での再検証が必要)。
SC3_CONFIRM_TICK:
    PUSH AF : PUSH BC : PUSH DE : PUSH HL
    LD HL,(SC3_CT_TIMER)
    LD A,H : OR L
    JR NZ,SC3CT_DEC_TIMER
    LD A,(SC3_CT_ROWS_LEFT)
    OR A
    JR NZ,SC3CT_HAVE_ROWS
    ; (2026-09-13、"サウンドが最後尻切れで止まってるので9回鳴らしたら
    ; 音止めて"): 新しいパスを開始する直前に、既にSC3_CT_MAX_PASSES回
    ; 開始済みならこれ以上は再生せず明示的にミュートしたまま停止する。
    LD A,(SC3_CT_PASS)
    CP SC3_CT_MAX_PASSES
    JR NC,SC3CT_STOPPED
    INC A
    LD (SC3_CT_PASS),A
    LD HL,SC3_CONFIRM_TICKS
    LD (SC3_CT_PTR),HL
    LD HL,BORDER_TABLE
    LD (SC3_CT_BORDER_PTR),HL
    LD A,SC3_CONFIRM_TICK_ROW_COUNT
    LD (SC3_CT_ROWS_LEFT),A
SC3CT_HAVE_ROWS:
    LD A,(SC3_CT_ROWS_LEFT)
    DEC A
    LD (SC3_CT_ROWS_LEFT),A
    LD HL,(SC3_CT_PTR)
    LD A,(HL) : INC HL : LD C,A
    LD A,2 : OUT (PSG_ADDR),A
    LD A,C : OUT (PSG_DATA),A      ; ch B tone period fine
    LD A,(HL) : INC HL : LD C,A
    LD A,3 : OUT (PSG_ADDR),A
    LD A,C : OUT (PSG_DATA),A      ; ch B tone period coarse
    LD A,(HL) : INC HL
    LD (SC3_CT_VOL),A              ; 音量はデューティ適用のため直接書かず保存
    LD A,(HL) : INC HL             ; duration (ticks) - round40と同じ
    DEC A                          ; off-by-one補正(このtick自体で1回目)
    LD (SC3_CT_TIMER),A
    XOR A : LD (SC3_CT_TIMER+1),A
    LD (SC3_CT_PTR),HL
    LD HL,(SC3_CT_BORDER_PTR)
    LD A,(HL) : INC HL
    LD (SC3_CT_BORDER_PTR),HL
    OUT (99h),A                    ; VDP R7(border/backdrop)データ書き込み
    NOP
    NOP
    LD A,87h : OUT (99h),A         ; reg7|80h = VDP R7 選択・確定
    NOP
    NOP
    JR SC3CT_APPLY_DUTY
SC3CT_DEC_TIMER:
    DEC HL
    LD (SC3_CT_TIMER),HL
SC3CT_APPLY_DUTY:
    ; (2026-09-13、"サウンドがデューティ比かかってない 前は50%だった
    ; はず"): 行の残りtickに関係なく毎tick位相を1進め、最下位ビットで
    ; ON/OFFを交互に切り替える(Round41のBGMデューティと同じ
    ; free-running位相+ANDマスク方式、mask=1で50%)。
    LD A,(SC3_CT_PHASE)
    INC A
    LD (SC3_CT_PHASE),A
    AND 1
    LD A,9 : OUT (PSG_ADDR),A
    JR NZ,SC3CT_DUTY_OFF
    LD A,(SC3_CT_VOL) : OUT (PSG_DATA),A
    JR SC3CT_DONE
SC3CT_DUTY_OFF:
    XOR A : OUT (PSG_DATA),A
SC3CT_DONE:
    POP HL : POP DE : POP BC : POP AF
    RET
SC3CT_STOPPED:
    ; SC3_CT_MAX_PASSES回再生し終えた後の恒久停止状態: 明示的にPSG
    ; (ch B音量)をミュートし、ボーダーも黒へ戻してからRET。SC3_CT_
    ; ROWS_LEFTは0のまま二度と進まないため、以後毎tickこの分岐を通る
    ; だけで無害(音は既に鳴っていないため上書きしても実害なし)。
    LD A,9 : OUT (PSG_ADDR),A : XOR A : OUT (PSG_DATA),A
    LD A,1 : OUT (99h),A
    NOP
    NOP
    LD A,87h : OUT (99h),A
    NOP
    NOP
    POP HL : POP DE : POP BC : POP AF
    RET

RUN_SCREEN3_SLIDESHOW:
    ; (2026-09-13、"アニメ中にボタン押されたらMission 1表示にスキップ"):
    ; 現在のSPを退避し、デバウンス用フラグを未武装(0)にリセットする。
    LD (SC3_SAVED_SP),SP
    XOR A : LD (SC3_SKIP_ARMED),A
    LD B,00h : LD C,0 : CALL WRTVDP
    LD B,00h : LD C,4 : CALL WRTVDP
    ; SCREEN1(Graphics1)からMulticolor(SCREEN3)への切替はVDP R1のM2
    ; ビット(bit3)を追加で立てるだけ - tools/screen3_test/screen3_
    ; test.asmで実機確認済みの0EAh(既存の0E2hへ08hを追加)。
    LD B,0EAh : LD C,1 : CALL WRTVDP
    LD B,01h : LD C,7 : CALL WRTVDP

    ; ネームテーブルは6枚とも完全同一(screen3_gen.py確認済み)のため
    ; ここで1回だけ書き込み、以後二度と触らない。
    ; (2026-09-13、"で、当然だが 99h99h98は DIEIでガードしないと表示
    ; 壊れる"): FLUSH_SHADOW_TO_VRAM(round97)と全く同じ理由 - この
    ; 書き込みはMulticolorモード切替(直前のWRTVDP)直後=既に表示期間
    ; 中に実行されるため、BIOS LDIRVM任せでは98hの29T間隔保証が無い。
    ; 同じ手動ループ(99hは待ち不要、98hは29T厳密ウェイト)+DI/EI保護
    ; へ書き換え。
    DI
    LD A,00h : OUT (99h),A
    LD A,58h : OUT (99h),A          ; VRAM書き込みアドレス=1800h、以後オートインクリメント(99hは待ち不要)
    LD HL,SC3_SHARED_NAME
    LD DE,SC3_SHARED_NAME_LEN
RSS_NAME_LOOP:
    LD A,(HL) : INC HL
    OUT (98h),A
    PUSH BC : POP BC : NOP : NOP    ; 98hは表示期間中29T必要
    DEC DE
    LD A,D : OR E
    JR NZ,RSS_NAME_LOOP
    EI

    ; このスライドショーの絵はいずれもスプライトパターンを持たない
    ; ため、明示的に全停止(既存のtitle自身の0D1hマーカーと同じ)。
    LD A,0D1h : LD HL,SPRATR : CALL WRTVRM

    ; 確認音のH.TIMIフックを設置(combined_test.asmのINIT_BGMと同じ
    ; "LD A,0C3h[JP opcode]:LD(HTIMI_HOOK),A:LD HL,<handler>:
    ; LD(HTIMI_HOOK+1),HL"パターン)。次のtickで即座に1行目を読み込ま
    ; せるためタイマー/残り行数を0にしておく。
    DI
    XOR A
    LD (SC3_CT_TIMER),A : LD (SC3_CT_TIMER+1),A : LD (SC3_CT_ROWS_LEFT),A
    LD (SC3_CT_PHASE),A            ; デューティ位相も0から開始(決定的な挙動のため)
    LD (SC3_CT_PASS),A             ; 再生回数カウンタも0から開始(9回で停止)
    LD A,0C3h : LD (HTIMI_HOOK),A
    LD HL,SC3_CONFIRM_TICK : LD (HTIMI_HOOK+1),HL
    EI

    ; (2026-09-12、実機フィードバック"アニメが指示と違う 流れは まず
    ; 1から6枚目を3フレ切り替え で7枚目の08を15フレ表示 ここまでを
    ; 3ループ その後09を30フレ 11を90フレ表示してMission 1表示"):
    ; 1-6枚目(各3フレーム、SHOW_SC3_IMGx自身に組み込み済み)+7枚目
    ; (=Epilogue1/08.SC3、15フレーム)を1周として3回繰り返し、その後
    ; Epilogue2(09.SC3)を30フレーム・Epilogue3(11.SC3)を90フレーム
    ; 表示してからMission 1(Stage1トランポリン)へ進む。確認音はもう
    ; 明示的にCALLしない - busy-waitループの最中もH.TIMIは発火し
    ; 続けるため、上記で設置したSC3_CONFIRM_TICKが自律的に鳴り続ける。
    ; (2026-09-13、"で、3ループの後に30フレ追加して 7枚目の表示時間
    ; 伸ばして で、1から6枚目の3フレウェイトを2フレに 他の処理で重く
    ; なったんで"): 1-6枚目は上記のWAIT_N_FRAMES統一化(B=2)により
    ; SHOW_SC3_IMGx側で対応済み。7枚目(Epilogue1)の待ちを15→30フレーム
    ; へ延長、3ループ終了直後(Epilogue2表示の前)に単独の30フレーム待ちを
    ; 追加。
    LD B,3
RSS_MAIN_LOOP:
    PUSH BC
    CALL SHOW_SC3_IMG1
    CALL SHOW_SC3_IMG2
    CALL SHOW_SC3_IMG3
    CALL SHOW_SC3_IMG4
    CALL SHOW_SC3_IMG5
    CALL SHOW_SC3_IMG6
    CALL SHOW_SC3_EPI1
    LD B,30
    CALL WAIT_N_FRAMES
    POP BC
    DJNZ RSS_MAIN_LOOP

    LD B,30
    CALL WAIT_N_FRAMES

    ; (2026-09-13、"8枚目は今30フレだと思うが60に 9枚目は120に"):
    ; 8枚目(Epilogue2/09.SC3)を30→60フレーム、9枚目(Epilogue3/
    ; 11.SC3)を90→120フレームへ延長。
    CALL SHOW_SC3_EPI2
    LD B,60
    CALL WAIT_N_FRAMES

    CALL SHOW_SC3_EPI3
    LD B,120
    CALL WAIT_N_FRAMES

    ; 呼び出し元(WFS_PROCEED)がこの直後にHTIMI_HOOKをbare RETへ戻し
    ; DIしてStage1へトランポリンする既存の設計に合わせ、ここでは
    ; チャンネルBの音量だけ明示的にミュートしておく(トランポリンまでの
    ; 僅かな間にもう1tick分鳴ってしまうのを防ぐ、既存のPLAY_CONFIRM_
    ; BEEP自身の「戻り際に必ずミュート」という流儀と同じ)。ボーダー色も
    ; 同様に明示的に黒(1)へ戻す - SC3_CONFIRM_TICKはループの途中の
    ; 任意の瞬間に停止しうるため、PLAY_CONFIRM_BEEPと違い自然に黒へ
    ; 収束している保証がない。
    ; (2026-09-13、"アニメ中にボタン押されたらMission 1表示にスキップ"):
    ; SC3_CHECK_SKIP(WAIT_1_FRAME_UNITから毎フレーム呼ばれる)がここへ
    ; SP巻き戻し+直接JPで到達しうる - 通常の「3ループ+締めの3枚を
    ; 全部見終えた」経路と全く同じ後片付けを通ることで、どちらの
    ; 経路でもPSG/ボーダーが確実に安全な状態に戻る。
RSS_CLEANUP:
    DI
    LD A,9 : OUT (PSG_ADDR),A : XOR A : OUT (PSG_DATA),A
    LD A,1 : OUT (99h),A : NOP : NOP : LD A,87h : OUT (99h),A : NOP : NOP
    RET

; 1枚目(基準フレーム): RLEをSHADOW_PGTへフル展開してからVRAMへ一括反映。
SHOW_SC3_IMG1:
    LD IX,SHADOW_PGT
    LD HL,SC3_IMG1_PGT_RLE : LD DE,SC3_IMG1_PGT_SEGMENTS : CALL DECOMPRESS_TO_RAM
    CALL FLUSH_SHADOW_TO_VRAM
    LD B,2 : JP WAIT_N_FRAMES
; 2〜6枚目: 直前フレームとのXOR差分をSHADOW_PGTへ適用してからVRAMへ
; 一括反映(必ずこの順番[1→2→3→4→5→6]で呼ぶ前提)。
SHOW_SC3_IMG2:
    LD IX,SHADOW_PGT
    LD HL,SC3_IMG2_PGT_XORDIFF : LD DE,SC3_IMG2_PGT_SEGMENTS : CALL APPLY_XOR_DIFF
    CALL FLUSH_SHADOW_TO_VRAM
    LD B,2 : JP WAIT_N_FRAMES
SHOW_SC3_IMG3:
    LD IX,SHADOW_PGT
    LD HL,SC3_IMG3_PGT_XORDIFF : LD DE,SC3_IMG3_PGT_SEGMENTS : CALL APPLY_XOR_DIFF
    CALL FLUSH_SHADOW_TO_VRAM
    LD B,2 : JP WAIT_N_FRAMES
SHOW_SC3_IMG4:
    LD IX,SHADOW_PGT
    LD HL,SC3_IMG4_PGT_XORDIFF : LD DE,SC3_IMG4_PGT_SEGMENTS : CALL APPLY_XOR_DIFF
    CALL FLUSH_SHADOW_TO_VRAM
    LD B,2 : JP WAIT_N_FRAMES
SHOW_SC3_IMG5:
    LD IX,SHADOW_PGT
    LD HL,SC3_IMG5_PGT_XORDIFF : LD DE,SC3_IMG5_PGT_SEGMENTS : CALL APPLY_XOR_DIFF
    CALL FLUSH_SHADOW_TO_VRAM
    LD B,2 : JP WAIT_N_FRAMES
SHOW_SC3_IMG6:
    LD IX,SHADOW_PGT
    LD HL,SC3_IMG6_PGT_XORDIFF : LD DE,SC3_IMG6_PGT_SEGMENTS : CALL APPLY_XOR_DIFF
    CALL FLUSH_SHADOW_TO_VRAM
    LD B,2 : JP WAIT_N_FRAMES

; 締めの3枚(いずれも直前フレームとのXOR差分、待ち時間は個別のため
; ここでは待たずRETするだけ - 呼び出し元RUN_SCREEN3_SLIDESHOWが
; 個別の待ち時間をCALLする)。
SHOW_SC3_EPI1:
    LD IX,SHADOW_PGT
    LD HL,SC3_EPI1_PGT_XORDIFF : LD DE,SC3_EPI1_PGT_SEGMENTS : CALL APPLY_XOR_DIFF
    JP FLUSH_SHADOW_TO_VRAM
SHOW_SC3_EPI2:
    LD IX,SHADOW_PGT
    LD HL,SC3_EPI2_PGT_XORDIFF : LD DE,SC3_EPI2_PGT_SEGMENTS : CALL APPLY_XOR_DIFF
    JP FLUSH_SHADOW_TO_VRAM
SHOW_SC3_EPI3:
    LD IX,SHADOW_PGT
    LD HL,SC3_EPI3_PGT_XORDIFF : LD DE,SC3_EPI3_PGT_SEGMENTS : CALL APPLY_XOR_DIFF
    JP FLUSH_SHADOW_TO_VRAM

; SHADOW_PGT(2048byte、RAM)->VRAM 0000hへ一括コピー。
;
; (2026-09-13、実機フィードバック3回目"ダメだな 表示は壊れたまま で、
; 99hはウェイトいらないとされてる で98hは表示期間では29T必要"): 前回
; までのDI/EI保護(round95)・99h書き込み後のNOP追加(round96)いずれも
; 解消せず、ユーザーからVDPタイミングの正確な訂正を受けた -
; **VDPレジスタポート(99h)は待ち不要、VRAMデータポート(98h)は
; "表示期間中"のみ29T必要**。このファイル自身の`DECOMPRESS_TITLE_BG`
; (INIT時、画面表示が始まる前に実行されるためOUT (98h)を無待機で連続
; 実行しても実機で正しく動作する既存コード)と、`combined_test.asm`の
; `WRITE_BULLET_BYTE_HL`(MAINLOOP中=表示期間中に実行されるため
; OUT (98h)の直後に29T相当の待ちを入れている既存コード)を比較すると、
; この区別は元々このプロジェクト自身のコードに一致していた。
; **真の根本原因はここ**: このスライドショーはSCREEN3が既に表示中の
; 状態で画像を切り替える(=表示期間中にVRAM転送する)にも関わらず、
; BIOS`LDIRVM`任せにしていたため、98hへの書き込み間隔がBIOS実装に
; 依存し29T保証が無かった。`DECOMPRESS_TITLE_BG`と同じ手動ループへ
; 書き換え、99h(アドレス設定)は待ち無し・98h(データ)は
; `combined_test.asm`と同じ29T厳密ウェイト(`PUSH BC:POP BC:NOP:NOP`、
; 11+10+4+4=29T)を毎バイト後に入れる。2048byteは8bitカウンタに収まら
; ないためDE 16bit down-counterでループ(`DECOMPRESS_TITLE_BG`の
; セグメント数カウンタと同じ方式)。DI/EIによる割り込み保護
; (round95の対策)自体は依然有効なので維持。CLAUDE.md恒久ルール通り
; OTIR等は不使用。
FLUSH_SHADOW_TO_VRAM:
    DI
    XOR A : OUT (99h),A
    LD A,40h : OUT (99h),A          ; VRAM書き込みアドレス=0000h、以後オートインクリメント(99hは待ち不要)
    LD HL,SHADOW_PGT
    LD DE,0800h                     ; 2048byte
FSTV_LOOP:
    LD A,(HL) : INC HL
    OUT (98h),A
    PUSH BC : POP BC : NOP : NOP    ; 98hは表示期間中29T必要(combined_test.asmのWRITE_BULLET_BYTE_HLと同じ厳密29T)
    DEC DE
    LD A,D : OR E
    JR NZ,FSTV_LOOP
    EI
    RET

; 自前の対称RLE(tools/title_screen/title_bg_gen.pyと同一フォーマット)
; をRAM上のSHADOW_PGTへそのまま展開する(1枚目の基準フレーム用)。
; HL=圧縮データ先頭、DE=セグメント数、IX=書き込み先(呼び出し前に
; SHADOW_PGTをセット)。このアセンブラはALU命令の(IX+d)直接オペランド
; 非対応のためLD経由の3段階(読む/合成/書く)は使わず単純代入のみ。
DECOMPRESS_TO_RAM:
    LD A,(HL) : INC HL
    OR A
    JP M,DTR_RUN
    AND 7Fh
    INC A
    LD B,A
DTR_LIT_LOOP:
    LD A,(HL) : INC HL
    LD (IX+0),A
    INC IX
    DJNZ DTR_LIT_LOOP
    JR DTR_NEXT
DTR_RUN:
    AND 7Fh
    INC A
    LD B,A
    LD A,(HL) : INC HL
DTR_RUN_LOOP:
    LD (IX+0),A
    INC IX
    DJNZ DTR_RUN_LOOP
DTR_NEXT:
    DEC DE
    LD A,D : OR E
    JR NZ,DECOMPRESS_TO_RAM
    RET

; 上と同じRLEフォーマットだが、展開した各バイトをSHADOW_PGTの現在値へ
; 「XOR適用」する(差分方式)。このアセンブラはALU命令の(IX+d)直接
; オペランドを非対応のため「LD A,(IX+0)で現在値を読む→XOR Cで差分値と
; 合成→LD (IX+0),Aで書き戻す」の3段階で行う。HL=圧縮データ先頭、
; DE=セグメント数、IX=適用先(呼び出し前にSHADOW_PGTをセット)。
APPLY_XOR_DIFF:
    LD A,(HL) : INC HL
    OR A
    JP M,AXD_RUN
    AND 7Fh
    INC A
    LD B,A
AXD_LIT_LOOP:
    LD A,(HL) : INC HL
    LD C,A
    LD A,(IX+0)
    XOR C
    LD (IX+0),A
    INC IX
    DJNZ AXD_LIT_LOOP
    JR AXD_NEXT
AXD_RUN:
    AND 7Fh
    INC A
    LD B,A
    LD A,(HL) : INC HL
    LD C,A
AXD_RUN_LOOP:
    LD A,(IX+0)
    XOR C
    LD (IX+0),A
    INC IX
    DJNZ AXD_RUN_LOOP
AXD_NEXT:
    DEC DE
    LD A,D : OR E
    JR NZ,APPLY_XOR_DIFF
    RET

; (2026-09-12、"アニメが指示と違う 流れは まず1から6枚目を3フレ切り替え
; で7枚目の08を15フレ表示 ここまでを3ループ その後09を30フレ 11を90フレ
; 表示してMission 1表示"): 任意フレーム数の待ち。割り込み/JIFFYに依存
; しない単純なDEデクリメントループ(CONFIRM_GAP_DELAY等と同じ
; 26T-state/iteration)を「1フレーム分」の単位ルーチンとして切り出し、
; 呼び出し元がB(フレーム数、1-255)をセットしてCALLする方式に一般化した
; (複数フレーム分をDE単体[16bit上限約476ms=約28フレーム分]で表現しようと
; すると桁あふれするため、CALL/DJNZの外側ループで束ねる - 1フレーム
; あたり数十T-stateのCALL/DJNZオーバーヘッドは59660T-stateの1フレーム
; 全体からすれば無視できる)。
; (2026-09-13、"3ループの後に30フレ追加して 7枚目の表示時間伸ばして
; 1から6枚目の3フレウェイトを2フレに 他の処理で重くなったんで"):
; 旧来の専用WAIT_3_FRAMES(3フレーム固定、独自のDE即値埋め込み)は撤去し、
; 1-6枚目もこのWAIT_N_FRAMESへ統一(呼び出し元でB=2をセット)。
; (2026-09-13、"アニメ中にボタン押されたらMission 1表示にスキップ"):
; 1フレーム分の待ちが終わるたびボタン状態を確認する - スライドショー
; 全体を通じてこのルーチンが唯一の「実時間で待っている」場所のため、
; ここに1箇所仕込むだけで1-6枚目/Epilogue1-3/単独待ちの全区間を
; カバーできる。Trashes: A(WAIT_1_FRAME_UNIT自体の既存のトラッシュ
; リストAF,DEの範囲内)。
SC3_WAIT_1F_COUNT EQU 2295   ; ≒1/60秒(59659.083T-state/26T-state per iter)
WAIT_1_FRAME_UNIT:
    LD DE,SC3_WAIT_1F_COUNT
WF1U_LOOP:
    DEC DE
    LD A,D : OR E
    JR NZ,WF1U_LOOP
    CALL SC3_CHECK_SKIP
    RET

; B=フレーム数(呼び出し元が事前にセット)。Trashes: AF,B,DE。
WAIT_N_FRAMES:
WNF_LOOP:
    PUSH BC
    CALL WAIT_1_FRAME_UNIT
    POP BC
    DJNZ WNF_LOOP
    RET

; デバウンス付きボタン検知: 開始直後の押しっぱなし(アニメ開始トリガー
; そのもの)では反応せず、一度A/B両トリガーとも離されたのを確認して
; から初めて「武装」し、以後どちらかが押された瞬間にSPをRUN_SCREEN3_
; SLIDESHOW開始時点へ強制的に巻き戻してRSS_CLEANUPへ直接JPする
; (SHOW_SC3_IMGx/WAIT_N_FRAMES等、何階層CALLの中にいても一発で
; 抜けられる)。Trashes: A。
SC3_CHECK_SKIP:
    LD A,1 : CALL GTTRIG
    OR A
    JR NZ,SC3CS_PRESSED
    LD A,3 : CALL GTTRIG
    OR A
    JR NZ,SC3CS_PRESSED
    LD A,1 : LD (SC3_SKIP_ARMED),A
    RET
SC3CS_PRESSED:
    LD A,(SC3_SKIP_ARMED)
    OR A
    RET Z
    LD SP,(SC3_SAVED_SP)
    JP RSS_CLEANUP

; ===== boss art tables, generated by title_gen.py - see that file =====
