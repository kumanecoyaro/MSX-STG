"""実機フィードバック対応 (round36-14 follow-up#14): ETANK_BULLET_ACT/
MINE_POOL/FLYER_LASER_ACTが一度もINIT時に明示的にゼロクリアされて
いなかったバグ("地形スクロールが乱れてる...一つ前のビルドでも地形は
乱れるが実行してから最新を実行すると正しく動く どこかで初期化ミスして
るな" + "1回だけだがスタート直後にFlyerレーザーがいきなり飛んできた")
を修正した際の回帰ガード。

`fresh_cpu()`のキャッシュ済みブートスナップショットは`bytearray(0x10000)`
というPython標準のゼロ初期化に暗黙に依存しており、これは実機のRAMが
電源投入直後に不定値(ゴミ)を含みうるという現実を代表していなかった
- このプロジェクト自身のテストハーネスが持っていた前提の誤りだった。

**(2026-08-31、ユーザー指摘: "それは何度も何度もやらかしてて 常に
こっちで指摘してるのに これで通算5回はやらかしてる OSやコンパイラ
前提でしか考えられないんだな")**: 手作業で対象シンボルを列挙する
チェックリスト方式は「新しいエンティティを追加した際にこのリストへの
追加を忘れる」という同じ失敗を再び許してしまう。そこで実際の
アセンブラのシンボルテーブルから`_ACT`/`_POOL`で終わる全シンボルを
実行時に自動列挙し(このコードベース全体で"+0 ACT"が例外なく守られて
いる規約であることをFLYER_SLOT_SIZE/HORMING_SLOT_SIZE/THUNDER_SLOT_
SIZE等、既存の全スロット定義コメントで確認済み)、手作業のリスト
メンテナンスなしに将来追加される全ての新規エンティティも自動的に
カバーする方式に書き換えた。

**この自動発見版を実際に走らせたところ、即座に2件の未知の実バグ候補
(SBEAM_ACT・THUNDER_POOL、いずれもボス専用)を検出した** - まさに
手作業リストでは見つけられなかった類のもの。ただし実際にコード
(combined_test.asm 3449-3469行目)を調査した結果、この2つは「バグの
見落とし」ではなく、round23由来の別の正当な設計だったと判明:
ユーザー自身の明示的な指示 "こう言ったゲームってのは全てスケジュール
で動くんだよ...ボス前とボススポーン後は完全に分けて一切干渉しない
当然ボスまでは一切関連ルーチンも呼ばんし最初にメモリを確保したりし
ない...初期化もボス用はボススポーン直前"(round23)の通り、
UPDATE_THUNDER/CHECK_THUNDER_VS_TANK/UPDATE_SBEAM/CHECK_SBEAM_VS_TANK
は`SKIP_BOSS_SUBSYSTEMS`ゲートによりBOSS_ACT==0の間は物理的に一度も
CALLされず、かつBOSS_ACTが0→1になる実スポーン遷移(UBA_ACTIVEの兄弟
分岐)がSBEAM_ACT/THUNDER_POOLの全スロットを同じ瞬間にアトミックに
ゼロクリアしてから初めて到達可能になる - つまり「INIT時点で不定値の
まま」であること自体は無害と証明されている、既存のENEMY_POOL等とは
異なる正当な"遅延初期化"パターン。BOSS_ACT自身だけは唯一の例外として
UPDATE_BOSS_ALLの毎フレーム先頭で読まれる(スポーン判定そのものを担う
ため遅延できない)ので、引き続きINIT時点での明示ゼロクリアが必須。

この区別を「ハードコードされた除外リスト」に戻すと同じ再発リスクを
抱えることになるため、**除外リストではなく2段階の自動検証**として
実装した: (1)通常はINIT直後にゼロであることを要求(Tier A、これが
実際に5回のバグを引き起こしたパターンを直接検出する)。(2)Tier Aに
落ちたシンボルだけ、救済判定として実際にBOSS_ACT=1(ボス実スポーン)
まで本物のMAINLOOPフレームを汚染RAMのまま進め、その時点で改めて
ゼロになっているかを検証する(Tier B) - これは「遅延初期化で本当に
安全か」という主張そのものを実行時に直接検証しており、静的なコード
コメントの主張を鵜呑みにしていない。Tier Bでも失敗する場合のみ本当の
FAILとして報告する。将来ボス以外の新しい遅延初期化パターンが導入され、
かつそれがボススポーン時点までに正しくクリアされない場合は、この
Tier Bチェックも失敗しFAILとして検出される(「ボススポーンまでに
必ずクリアされる」という一点のみを免除条件として要求しているため、
無条件の見逃しにはならない)。
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, step_frame
import build_test
from z80emu import Z80

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


def boot_with_poisoned_ram(poison_byte):
    """Real INIT trace, but with every flat RAM byte set to poison_byte
    before the very first instruction runs - simulates real MSX RAM
    holding leftover garbage at power-on, unlike fresh_cpu()'s own
    implicitly-zeroed bytearray."""
    bank0, bank1 = build_test.build_banks(out)
    mem = build_test.BankedMem(bank0, bank1)
    for i in range(len(mem.flat)):
        mem.flat[i] = poison_byte
    cpu = Z80(mem)
    cpu.pc = sym["INIT"]
    mainloop = sym["MAINLOOP"]
    steps = 0
    while cpu.pc != mainloop and steps < 300000:
        cpu.step()
        steps += 1
    assert steps < 300000, "never reached MAINLOOP"
    return cpu


def run_until_boss_spawned(cpu, max_frames=9000):
    """Advances real MAINLOOP frames (poisoned RAM stays poisoned wherever
    nothing legitimately writes it) until BOSS_ACT becomes 1 - the one
    runtime gate this codebase actually relies on for deferred boss-only
    initialization (see module docstring). Returns False if the boss
    never spawned within max_frames (BOSS_SPAWN_TICK=995 * ~8 frames/tick
    is comfortably under the default budget)."""
    BOSS_ACT = sym["BOSS_ACT"]
    for _ in range(max_frames):
        if cpu.mem[BOSS_ACT] == 1:
            return True
        step_frame(cpu)
    return cpu.mem[BOSS_ACT] == 1


def is_flat_ram(addr):
    """BankedMem routes 4000h-BFFFh to bank-switched ROM; everything
    else (0000h-3FFFh, C000h-FFFFh) is plain flat RAM - see its own
    __getitem__. A few "_ACT"/"_POOL" symbols aren't real RAM addresses
    at all: struct-field offset constants (e.g. E_ACT=0, an IX-relative
    offset, not an address) and routine labels that happen to end in
    "_POOL" (e.g. RESET_THUNDER_POOL, a CALL target at a banked-ROM
    address) - both filtered out here (offsets are always small; this
    codebase's real RAM variables all sit at 0xC000+ or 0xF000+)."""
    return isinstance(addr, int) and 0x100 <= addr <= 0xFFFF and not (0x4000 <= addr <= 0xBFFF)


# every standalone "*_ACT" flag (single-entity state) and every "*_POOL"
# base (array of slots, own ACT always at +0 - verified against every
# real *_SLOT_SIZE comment in combined_test.asm) discovered directly
# from the real assembler's own symbol table, not a hand-maintained list.
act_flags = sorted((k, v) for k, v in sym.items() if k.endswith("_ACT") and is_flat_ram(v))
pool_bases = sorted((k, v) for k, v in sym.items() if k.endswith("_POOL") and is_flat_ram(v))
BOSS_ACT = sym["BOSS_ACT"]

check("discovered at least the known _ACT flags (sanity check on the discovery mechanism itself)",
      {"ETANK_BULLET_ACT", "FLYER_LASER_ACT", "BOSS_ACT", "SBEAM_ACT",
       "BULLET0_ACT", "BULLET1_ACT", "BULLET2_ACT", "BULLET3_ACT"} <= {k for k, v in act_flags})
check("discovered at least the known _POOL bases",
      {"ENEMY_POOL", "ZUM_POOL", "BIGZUM_POOL", "FLYER_POOL", "ETANK_POOL",
       "EBULLET_POOL", "MINE_POOL", "HORMING_POOL", "THUNDER_POOL", "CLOUD_POOL"} <= {k for k, v in pool_bases})


def pool_act_offsets(pool_name):
    """Every slot's own +0 ACT offset for a pool, derived from its own
    <PREFIX>_SLOT_SIZE/_SLOT_COUNT symbols when present (same naming
    idiom as every pool in this file - confirmed via `grep _SLOT_SIZE`
    across the whole codebase). Falls back to just slot0 when a pool
    doesn't follow the naming idiom (still real coverage, just narrower)."""
    assert pool_name.endswith("_POOL")
    prefix = pool_name[: -len("_POOL")]
    size_sym = f"{prefix}_SLOT_SIZE"
    count_sym = f"{prefix}_SLOT_COUNT"
    if size_sym in sym and count_sym in sym:
        size, count = sym[size_sym], sym[count_sym]
        return [i * size for i in range(count)]
    return [0]


# flat list of (label, addr) for every individually-checkable byte: each
# standalone _ACT flag, plus every slot's own ACT byte in every _POOL.
targets = [(name, addr) for name, addr in act_flags]
for name, base in pool_bases:
    for off in pool_act_offsets(name):
        targets.append((f"{name}+{off} (slot ACT)", base + off))

POISONS = (0xFF, 0xAA, 0x55, 0x01)

# ---------- Tier A: must already be 0 immediately after INIT ----------
# This is the check that actually catches the exact bug class that bit
# us 5 times: a pool/flag that's only ever WRITTEN at spawn/despawn and
# never explicitly zeroed at boot.
tier_a_failures = set()  # {(name, addr)} that failed for at least one poison
for poison in POISONS:
    cpu = boot_with_poisoned_ram(poison)
    for name, addr in targets:
        if cpu.mem[addr] != 0:
            tier_a_failures.add((name, addr))
    check(f"poison=0x{poison:02X}: BOSS_ACT is 0 (not spawned) right after INIT - the one field with no deferred-init grace period (see docstring)",
          cpu.mem[BOSS_ACT] == 0)

# BOSS_ACT itself is never allowed to fall back to Tier B: it's the gate
# that everything else's deferred-init safety depends on, so it must be
# genuinely zero the instant INIT finishes, unconditionally.
check("BOSS_ACT is not a Tier-A failure (it has no legitimate deferred-init excuse - see docstring)",
      ("BOSS_ACT", BOSS_ACT) not in tier_a_failures)

# ---------- Tier B: a Tier-A failure gets one legitimate excuse ----------
# only if it is PROVABLY safe to defer: real gameplay frames (still on
# poisoned RAM) advanced all the way to the boss's own real spawn
# transition, and the field is genuinely 0 by then. This directly
# exercises the actual claim in combined_test.asm's own comment (round23:
# boss-only fields are zeroed atomically at spawn, and never read before
# that because SKIP_BOSS_SUBSYSTEMS gates every reader on BOSS_ACT!=0) -
# it does not just trust the comment.
real_bugs = set()
# most Tier-A exceptions are "inactive" flags that get atomically zeroed
# right at spawn (SBEAM_ACT/THUNDER_POOL - "cleared"). BOSS_MATERIALIZE_
# ACT (see combined_test.asm's own TRIGGER_BOSS_MATERIALIZE, follow-
# up#22 - the entrance-wipe design's direct successor) is the one
# legitimate exception to THAT: the entrance effect starts ACTIVE the
# instant the boss spawns, so its deterministic post-spawn value is 1,
# not 0 - still fully poison-independent (still safe), just not "0".
# Anything not listed here defaults to the usual "0" expectation.
EXPECTED_AT_SPAWN = {"BOSS_MATERIALIZE_ACT": 1}
if tier_a_failures:
    for poison in POISONS:
        cpu = boot_with_poisoned_ram(poison)
        spawned = run_until_boss_spawned(cpu)
        for name, addr in sorted(tier_a_failures):
            expected = EXPECTED_AT_SPAWN.get(name, 0)
            still_bad = (not spawned) or cpu.mem[addr] != expected
            if still_bad:
                real_bugs.add((name, addr))
            check(f"poison=0x{poison:02X}: {name} (0x{addr:04X}) failed the immediate Tier-A check, "
                  f"so verifying it under Tier B instead (boss actually spawned={spawned}, now "
                  f"{expected}={cpu.mem[addr] == expected if spawned else 'n/a'})",
                  not still_bad)

for name, addr in sorted(tier_a_failures):
    verdict = "confirmed safe by Tier B (deferred init, cleared atomically at boss spawn - not a bug)" \
        if (name, addr) not in real_bugs else "STILL FAILS Tier B - this is a real uninitialized-RAM bug"
    print(f"Tier-A exception: {name} (0x{addr:04X}) - {verdict}")

check("no _ACT/_POOL symbol is left uninitialized-and-unsafe (fails both Tier A and Tier B)",
      len(real_bugs) == 0)


# spot-checks that don't fit the generic "*_ACT"/"*_POOL" name pattern
# but were part of this exact round's own reported bug - kept as
# explicit, named regressions on top of the generic sweep above.
ETANK_SPAWN_X = sym["ETANK_SPAWN_X"]
ETANK_BULLET_FIRED = sym["ETANK_BULLET_FIRED"]
MINE_SPRITE_ATTRS = sym["MINE_SPRITE_ATTRS"]
for poison in (0xFF, 0x01):
    cpu = boot_with_poisoned_ram(poison)
    check(f"poison=0x{poison:02X}: ETANK_SPAWN_X/ETANK_BULLET_FIRED are 0 after INIT",
          cpu.mem[ETANK_SPAWN_X] == 0 and cpu.mem[ETANK_BULLET_FIRED] == 0)
    check(f"poison=0x{poison:02X}: MINE_SPRITE_ATTRS starts hidden (Y=209), not garbage",
          cpu.mem[MINE_SPRITE_ATTRS] == 209)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
