"""Stage1: ボススポーン条件の再設計(round135follow-up13)の検証。

ユーザー指示: "前にも言ったがすでにJsonのスケジュールはTick通りに進行
していない 原因は恐らくエネミー6だがこれはどうでもいい 順番通りに出れば
な なのでボススポーン条件は固定Tickではなく3体目が消えたあとにしなきゃ
ダメって事だな Tick1000以上かつ敵が画面のこってない事だな 残っていない
かのチェックは常にやったら無駄なんで1000を超えてスポーン条件が満たされ
たら初めて敵が居ないか調べろ"。

従来はSPAWN_THRESHOLDSの最終エントリ(index479、閾値992)がSSC_FIREから
BOSS_SPAWNを直接ディスパッチする固定Tick駆動だったが、これを撤去。代わり
に新設CHECK_BOSS_TRIGGER(MAINLOOP、SKIP_G8直後で毎フレーム無条件に呼ば
れる)が独立に「GAME_TICK>=1024(高byteが4以上、'1000を超えて'の近似)
かつ全ての敵プールが空」を判定し、満たされたらBOSS_SPAWNへ直接ジャンプ
する。BOSS_STATE(0=未出現、BOSS_SPAWNが1にセット)がそのまま一回性の
ラッチを兼ねる。

tools/verify_boss_dfl_clear.py等と同じ「mini_z80asm.Assemblerで直接
アセンブル+call_routine/run_until_pcの一回性検証スクリプト」の作法に
倣う。
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from mini_z80asm import Assembler
from z80emu import Z80

REPO_ROOT = os.path.join(os.path.dirname(__file__), '..')
with open(os.path.join(REPO_ROOT, 'src', 'CYBER SHMUP.asm'), encoding="utf-8") as f:
    text = f.read()

asm = Assembler(text)
out = asm.assemble()
sym = asm.symtab
mem0 = bytearray(65536)
for addr, val in out.items():
    mem0[addr & 0xFFFF] = val & 0xFF
mem0[sym["MISSION_DELAY_3SEC"] + 1] = 1

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


def fresh():
    return Z80(bytearray(mem0))


def run_until_pc(z, target_pc, max_instr=300000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


def boot(z):
    z.pc = sym["INIT"]
    run_until_pc(z, sym["MAINLOOP"])


def step_frame(z):
    z.pc = sym["MAINLOOP"]
    z.step()
    run_until_pc(z, sym["MAINLOOP"])


def call_routine(z, entry_addr, max_instr=300000):
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = entry_addr
    run_until_pc(z, 0x0000, max_instr)


GAME_TICK = sym["GAME_TICK"]
BOSS_STATE = sym["BOSS_STATE"]
CHECK_BOSS_TRIGGER = sym["CHECK_BOSS_TRIGGER"]
SCAN_POOL_ACTIVE = sym["SCAN_POOL_ACTIVE"]
ENEMY_POOL = sym["ENEMY_POOL"]
ENEMY_SLOT_COUNT = sym["ENEMY_SLOT_COUNT"]
ENEMY_SLOT_SIZE = sym["ENEMY_SLOT_SIZE"]
ENEMY6_POOL = sym["ENEMY6_POOL"]
ENEMY6_SLOTS = sym["ENEMY6_SLOTS"]
ENEMY6_ACTIVE_COUNT = sym["ENEMY6_ACTIVE_COUNT"]
ENEMY3_WAVE_POOL = sym["ENEMY3_WAVE_POOL"]
ENEMY3_WAVE_SLOTS = sym["ENEMY3_WAVE_SLOTS"]
E2A_ACTIVE = sym["E2A_ACTIVE"]
E2B_ACTIVE = sym["E2B_ACTIVE"]
EBUZ_SLOT0 = sym["EBUZ_SLOT0"]
EBUZ_SLOT1 = sym["EBUZ_SLOT1"]
EBUZ_OFS_ACT = sym["EBUZ_OFS_ACT"]
EBUZ_EXPL_QUEUE_COUNT = sym["EBUZ_EXPL_QUEUE_COUNT"]


def wr16(z, addr, val):
    z.wr(addr, val & 0xFF)
    z.wr(addr + 1, (val >> 8) & 0xFF)


def clear_all_pools(z):
    """全ての敵プール/フラグを非活性状態にする(=ボス出現条件の
    「敵が画面に残っていない」を満たす下地)。"""
    for i in range(ENEMY_SLOT_COUNT):
        z.wr(ENEMY_POOL + i * ENEMY_SLOT_SIZE, 0)
    for i in range(ENEMY6_SLOTS):
        z.wr(ENEMY6_POOL + i * 4, 0)
    z.wr(ENEMY6_ACTIVE_COUNT, 0)
    for i in range(ENEMY3_WAVE_SLOTS):
        z.wr(ENEMY3_WAVE_POOL + i * 4, 0)
    z.wr(E2A_ACTIVE, 0)
    z.wr(E2B_ACTIVE, 0)
    z.wr(EBUZ_SLOT0 + EBUZ_OFS_ACT, 0)
    z.wr(EBUZ_SLOT1 + EBUZ_OFS_ACT, 0)
    z.wr(EBUZ_EXPL_QUEUE_COUNT, 0)


def arm_ready(z, tick_hi=4):
    """CHECK_BOSS_TRIGGERの発火条件のうち「Tick充足+全プール空」だけを
    満たした状態にする(BOSS_STATEは呼び出し側で個別に設定)。"""
    clear_all_pools(z)
    wr16(z, GAME_TICK, tick_hi * 256)


# ============================================================
# 1. SCAN_POOL_ACTIVE単体: 全スロット非活性ならZ(A=0)、どこか1つでも
#    活性ならNZ(A=1)を返す。境界(最後のスロット)も正しく見る。
# ============================================================
def scan(z, base, count, stride):
    z.b = count
    z.h = (base >> 8) & 0xFF
    z.l = base & 0xFF
    z.d = (stride >> 8) & 0xFF
    z.e = stride & 0xFF
    call_routine(z, SCAN_POOL_ACTIVE)
    return z.a


z1 = fresh()
boot(z1)
for i in range(8):
    z1.wr(0xE800 + i * 4, 0)
check("SCAN_POOL_ACTIVE: 全8スロット非活性ならA=0(Z)",
      scan(z1, 0xE800, 8, 4) == 0)

z2 = fresh()
boot(z2)
for i in range(8):
    z2.wr(0xE800 + i * 4, 0)
z2.wr(0xE800 + 3 * 4, 1)  # 中間のスロットだけ活性
check("SCAN_POOL_ACTIVE: 中間スロット(index3)が活性ならA!=0(NZ)",
      scan(z2, 0xE800, 8, 4) != 0)

z3 = fresh()
boot(z3)
for i in range(8):
    z3.wr(0xE800 + i * 4, 0)
z3.wr(0xE800 + 7 * 4, 1)  # 最後のスロットだけ活性(境界チェック)
check("SCAN_POOL_ACTIVE: 最後のスロット(index7、境界)が活性でも正しく検出",
      scan(z3, 0xE800, 8, 4) != 0)

z4 = fresh()
boot(z4)
for i in range(8):
    z4.wr(0xE800 + i * 4, 0)
z4.wr(0xE800 + 8 * 4, 1)  # count=8の"次"(index8)は範囲外、見てはいけない
check("SCAN_POOL_ACTIVE: count=8で止まる(範囲外index8の値は無視される)",
      scan(z4, 0xE800, 8, 4) == 0)

# ============================================================
# 2. CHECK_BOSS_TRIGGER: BOSS_STATE!=0なら即RET(二重スポーン防止)。
#    Tick充足+全プール空という「発火するはず」の状況を用意しても、
#    既にBOSS_STATEが立っていれば再度BOSS_SPAWNは呼ばれない。
# ============================================================
z5b = fresh()
boot(z5b)
arm_ready(z5b)
z5b.wr(BOSS_STATE, 1)
z5b.wr(sym["BOSS_PHASE"], 99)  # BOSS_SPAWNが呼ばれれば1に上書きされるはずの番兵
call_routine(z5b, CHECK_BOSS_TRIGGER)
check("BOSS_STATE!=0の間はBOSS_SPAWN自体が呼ばれない"
      "(番兵BOSS_PHASE=99がBOSS_SPAWNの'LD A,1:LD(BOSS_PHASE)'で"
      "上書きされていない)",
      z5b.rd(sym["BOSS_PHASE"]) == 99)

# ============================================================
# 3. CHECK_BOSS_TRIGGER: GAME_TICKの高byteが4未満(<1024)の間は、
#    全プールが空でもプール走査自体を行わず発火しない
#    ("1000を超えてスポーン条件が満たされたら初めて敵が居ないか調べろ")。
# ============================================================
for hi in (0, 1, 2, 3):
    zt = fresh()
    boot(zt)
    clear_all_pools(zt)
    wr16(zt, GAME_TICK, hi * 256 + 200)  # < 1024 のどこか
    zt.wr(BOSS_STATE, 0)
    call_routine(zt, CHECK_BOSS_TRIGGER)
    check(f"GAME_TICK高byte={hi}(<1024)では全プール空でもBOSS_STATEは0のまま",
          zt.rd(BOSS_STATE) == 0)

zt2 = fresh()
boot(zt2)
arm_ready(zt2, tick_hi=4)  # GAME_TICK=1024ちょうど、高byte=4
zt2.wr(BOSS_STATE, 0)
call_routine(zt2, CHECK_BOSS_TRIGGER)
check("GAME_TICK高byte=4(=1024、'1000を超えて'の閾値ちょうど)かつ全プール空"
      "ならBOSS_SPAWNが呼ばれBOSS_STATE=1になる",
      zt2.rd(BOSS_STATE) == 1)

# ============================================================
# 4. CHECK_BOSS_TRIGGER: Tick充足でも、いずれかのプール/フラグが
#    非空なら発火しない(6経路それぞれを個別に検証)。
# ============================================================
def blocked_by(setup_fn, label):
    zz = fresh()
    boot(zz)
    arm_ready(zz)
    zz.wr(BOSS_STATE, 0)
    setup_fn(zz)
    call_routine(zz, CHECK_BOSS_TRIGGER)
    check(f"Tick充足でも{label}が非空ならBOSS_SPAWNは呼ばれない(BOSS_STATE=0のまま)",
          zz.rd(BOSS_STATE) == 0)


blocked_by(lambda z: z.wr(ENEMY_POOL, 1), "ENEMY_POOL(slot0)")
blocked_by(lambda z: z.wr(ENEMY_POOL + (ENEMY_SLOT_COUNT - 1) * ENEMY_SLOT_SIZE, 1),
           "ENEMY_POOL(最終slot、境界)")
blocked_by(lambda z: (z.wr(ENEMY6_POOL + 5 * 4, 1), z.wr(ENEMY6_ACTIVE_COUNT, 1)),
           "ENEMY6_POOL")  # round135follow-up15: CHECK_BOSS_TRIGGERはO(1)化された
           # ENEMY6_ACTIVE_COUNTを見るため、実際のスポーンと同じくスロット+
           # カウンタ両方をセットする必要がある(スロットだけでは検出されない)
blocked_by(lambda z: z.wr(ENEMY3_WAVE_POOL + 2 * 4, 1), "ENEMY3_WAVE_POOL")
blocked_by(lambda z: z.wr(E2A_ACTIVE, 1), "E2A_ACTIVE")
blocked_by(lambda z: z.wr(E2B_ACTIVE, 1), "E2B_ACTIVE")
blocked_by(lambda z: z.wr(EBUZ_SLOT0 + EBUZ_OFS_ACT, sym["EBUZ_ST_FIRE"]), "EBUZ_SLOT0.ACT")
blocked_by(lambda z: z.wr(EBUZ_SLOT1 + EBUZ_OFS_ACT, sym["EBUZ_ST_ENTER"]), "EBUZ_SLOT1.ACT")
blocked_by(lambda z: z.wr(EBUZ_EXPL_QUEUE_COUNT, 3),
           "EBUZ_EXPL_QUEUE_COUNT(死亡演出再生中)")

# ============================================================
# 5. CHECK_BOSS_TRIGGER: Tick充足+全プール空なら発火する
#    (EBULLET_POOLは"敵"に含めない、という判断の確認 - 弾だけが
#    残っていてもブロックされない)。
# ============================================================
z6 = fresh()
boot(z6)
arm_ready(z6)
z6.wr(BOSS_STATE, 0)
EBULLET_POOL = sym["EBULLET_POOL"]
EBULLET_SLOTS = sym["EBULLET_SLOTS"]
for i in range(EBULLET_SLOTS):
    z6.wr(EBULLET_POOL + i * 4, 1)  # 敵弾は全スロットアクティブのまま
call_routine(z6, CHECK_BOSS_TRIGGER)
check("EBULLET_POOL(敵弾)が全スロット活性でも、他の敵プールが全て空なら"
      "ボスは正常にスポーンする(敵弾は'敵が居ない'判定の対象外という設計)",
      z6.rd(BOSS_STATE) == 1)

# ============================================================
# 6. CHECK_BOSS_TRIGGER: 全条件を満たした発火が、実際にBOSS_SPAWN本体
#    (VRAM転送・BOSS_PHASE/BOSS_STATEセット・BOSS_SETUP_TILE_SPRITE)
#    まで完走することを確認(単なるBOSS_STATE書き換えではないこと)。
# ============================================================
z7 = fresh()
boot(z7)
arm_ready(z7)
z7.wr(BOSS_STATE, 0)
call_routine(z7, CHECK_BOSS_TRIGGER)
check("発火時、BOSS_PHASEも1にセットされる(BOSS_SPAWN本体まで到達した証拠)",
      z7.rd(sym["BOSS_PHASE"]) == 1)
check("発火時、BOSS_ROW/BOSS_COLも0にリセットされる",
      z7.rd(sym["BOSS_ROW"]) == 0 and z7.rd(sym["BOSS_COL"]) == 0)

# ============================================================
# 7. 実MAINLOOP経由: SPAWN_SCHEDULE_CHECK側の固定Tick駆動は撤去された
#    ので、GAME_TICKをスケジュール終了(index>=479)を超えて直接大きく
#    進めても、CHECK_BOSS_TRIGGERの独立判定だけでボスが出現すること。
# ============================================================
z8 = fresh()
boot(z8)
arm_ready(z8, tick_hi=4)
wr16(z8, sym["SPAWN_NEXT_INDEX"], 999)  # スケジュール自体は完全に終了済み
z8.wr(BOSS_STATE, 0)
for _ in range(8):  # SKIP_G8ゲート(TICK AND 7==0)を確実に1回踏むだけの余裕
    step_frame(z8)
check("実MAINLOOP経由でも、スケジュール完了後(SPAWN_NEXT_INDEX>=479)に"
      "GAME_TICK>=1024かつ敵不在ならボスが出現する"
      "(ボス出現がスケジュールの終端エントリに依存しなくなったことの確認)",
      z8.rd(BOSS_STATE) == 1)

# ============================================================
# 8. 自己検証: MAINLOOPのCALL CHECK_BOSS_TRIGGERを無効化すると、
#    上と全く同じ状況でもボスが永久に出現しなくなる。
# ============================================================
def _regress_no_check_boss_trigger():
    broken_mem = bytearray(mem0)
    target = CHECK_BOSS_TRIGGER
    pat = bytes([0xCD, target & 0xFF, (target >> 8) & 0xFF])
    idx = bytes(broken_mem).find(pat)
    if idx < 0:
        raise RuntimeError("CALL CHECK_BOSS_TRIGGER not found in MAINLOOP")
    broken_mem[idx] = 0x00
    broken_mem[idx + 1] = 0x00
    broken_mem[idx + 2] = 0x00
    zz = Z80(broken_mem)
    zz.pc = sym["INIT"]
    run_until_pc(zz, sym["MAINLOOP"])
    for i in range(ENEMY_SLOT_COUNT):
        zz.wr(ENEMY_POOL + i * ENEMY_SLOT_SIZE, 0)
    for i in range(ENEMY6_SLOTS):
        zz.wr(ENEMY6_POOL + i * 4, 0)
    zz.wr(ENEMY6_ACTIVE_COUNT, 0)
    for i in range(ENEMY3_WAVE_SLOTS):
        zz.wr(ENEMY3_WAVE_POOL + i * 4, 0)
    zz.wr(E2A_ACTIVE, 0); zz.wr(E2B_ACTIVE, 0)
    zz.wr(EBUZ_SLOT0 + EBUZ_OFS_ACT, 0); zz.wr(EBUZ_SLOT1 + EBUZ_OFS_ACT, 0)
    zz.wr(EBUZ_EXPL_QUEUE_COUNT, 0)
    zz.wr(BOSS_STATE, 0)
    zz.wr(GAME_TICK, 0); zz.wr(GAME_TICK + 1, 4)
    for _ in range(8):
        zz.pc = sym["MAINLOOP"]; zz.step(); run_until_pc(zz, sym["MAINLOOP"])
    return zz.rd(BOSS_STATE)


check("自己検証: MAINLOOPのCALL CHECK_BOSS_TRIGGERを無効化すると、"
      "上と同じ状況(Tick充足+全プール空)でもボスは出現しない"
      "(=このフックが実際に効いていることの確認)",
      _regress_no_check_boss_trigger() == 0)

# ============================================================
# 9. round135follow-up16("ボスを別バンクに移してくれ だいぶ削減出来る
#    はずだ"): BOSS_PATTERNS(ボス本体64x64グラフィック、512byte)は
#    ソースからDB展開を削除し、Titleが起動時に共有バンク(Comb bank6)
#    からRAM(BOSS_PATTERNS EQU 0CD8Dh)へ事前コピーする方式へ変更した。
#    Stage1単体のこのテストはTitleを経由しないため、実機同様に
#    BOSS_SPAWN直前でRAMへ実データをpokeした上で、BOSS_SPAWN自身の
#    LDIRVM(RAM→VRAM、宛先192*8~255*8)が正しく機能することだけを
#    検証する(=RAMコピー先アドレス・LDIRVMの転送先アドレス/バイト数
#    が今回の変更後も一致していることの確認)。
# ============================================================
with open(os.path.join(REPO_ROOT, 'tools', 'bgm_data', 'stage1_boss_chardata.bin'), 'rb') as f:
    _real_boss_patterns = f.read()
assert len(_real_boss_patterns) == 512

z9 = fresh()
boot(z9)
arm_ready(z9)
z9.wr(BOSS_STATE, 0)
BOSS_PATTERNS = sym["BOSS_PATTERNS"]
for i, b in enumerate(_real_boss_patterns):
    z9.wr(BOSS_PATTERNS + i, b)
call_routine(z9, CHECK_BOSS_TRIGGER)
check("BOSS_SPAWN発火時、BOSS_PATTERNS(RAM、0CD8Dh)の実データが"
      "VRAM上のcode192-255パターンジェネレータ領域(192*8~256*8)へ"
      "そのままLDIRVMされる(RAM移設後もボス本体グラフィックが正しく"
      "表示されることの確認)",
      bytes(z9.vram[192 * 8:192 * 8 + 512]) == _real_boss_patterns)

# ---- self-verification: poison BOSS_PATTERNS RAM with different bytes ----
# ---- and confirm the VRAM check above would actually detect a mismatch ----
z10 = fresh()
boot(z10)
arm_ready(z10)
z10.wr(BOSS_STATE, 0)
for i in range(512):
    z10.wr(BOSS_PATTERNS + i, (i * 37 + 5) & 0xFF)  # deliberately NOT the real data
call_routine(z10, CHECK_BOSS_TRIGGER)
check("自己検証: BOSS_PATTERNS RAMを実データと異なる内容で汚染すると、"
      "VRAM上の対応領域もその異なる内容になる(=上の一致チェックが"
      "実際にRAM内容の違いを検出できることの確認)",
      bytes(z10.vram[192 * 8:192 * 8 + 512]) != _real_boss_patterns and
      bytes(z10.vram[192 * 8:192 * 8 + 512]) == bytes((i * 37 + 5) & 0xFF for i in range(512)))

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILED:")
    for f in fail:
        print(" -", f)
    sys.exit(1)
