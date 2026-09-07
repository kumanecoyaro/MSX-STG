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

    ; (2026-09-07、"タイトル画面でボタン押下でサウンド追加"): チャンネルB
    ; は上記INIT_BGMがR7で常時トーン有効のまま用意しているが、このファイル
    ; 自身はBGM再生を行わない設計のため音量ミュートのまま遊休状態 - R7を
    ; 一切変更せず(トーンA自体は無効のまま)、そのチャンネルBを一時的に
    ; 借りて短い確認ビープを鳴らすだけで実現できる。Stage1へのバンク切替
    ; トランポリンより前、このファイル自身の時間軸内で完結させる(切替後は
    ; H.TIMI/PSG状態がStage1側の管理下に移るため)。
    CALL PLAY_CONFIRM_BEEP

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
; もの。R2/R3(チャンネルBトーン周期)・R9(チャンネルB音量)のみを操作、
; R7は一切変更しない(チャンネルBは元々INIT_BGMが常時トーン有効のまま
; 用意している遊休チャンネル)。53行×2回(短い無音ギャップを挟む)で
; 全体の合成音を構成する。Trashes: AF,BC,DE,HL。
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
    LD B,CONFIRM_STEP_COUNT
PCB_ROW_LOOP:
    PUSH BC
    CALL PCB_PLAY_ONE_ROW
    POP BC
    DJNZ PCB_ROW_LOOP
    RET

; HLが指す5byte行を1行分再生し、HLを+5だけ進めて戻る。
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
INIT_BGM:
    LD A,2                       ; standalone bgm-dataバンク(Combでは6へパッチ)
    LD (7000h),A
    LD HL,08000h : LD DE,0C000h : LD BC,078h : LDIR   ; 周期テーブル(60note*2)
    LD HL,08078h : LD DE,0C078h : LD BC,0628h : LDIR  ; ALONE_FIGHTER chB+chC
    LD HL,08E32h : LD DE,0C910h : LD BC,032Eh : LDIR  ; TryZ chB+chC(Stage1ボス用)
    LD HL,0931Bh : LD DE,0CC42h : LD BC,010Dh : LDIR  ; StageClear chB+chC+chA(Stage1ステージクリア用)
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

; ===== boss art tables, generated by title_gen.py - see that file =====
