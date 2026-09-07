"""Converts Sasapi (the boss, 64x64, Sprite Editor JSON) into MSX
hardware sprite pattern data - same TL/BL/TR/BR-per-16x16-quadrant
approach as bigzum_gen.py/flyer_gen.py, just a 4x4 grid of 16x16
quadrants (16 of them) instead of a 2x2 one, since 64x64 is 4x the
linear size of the 32x32 sprites everything else here uses.

Unlike BigZum/Flyer, Sasapi does NOT get its own permanent pattern-code
allocation - "自機以外はもうスポーンしないんで オールフリー": by the
time the boss can spawn (BOSS_SPAWN_TICK=999), every ordinary enemy
type has been refusing to spawn for 49 GAME_TICKs already
(ENEMY_SPAWN_STOP_TICK=950 - see SPAWN_STOPPED), so their own pattern-
VRAM is free to reuse. Sasapi's 16 quadrants x4 patterns = exactly 64
slots, exactly BigZum's own whole footprint (PAT_BIGZUM..+63, all 4 of
its pose/facing groups) - reused wholesale rather than carving out a
5th permanent block this file doesn't have room for (see
combined_test.asm's own pattern-code budget comment: Flyer's own last
group already ends at 251, only 4 slots free above it). Loaded into
VRAM fresh at boss-spawn time (once - the boss never despawns, so this
only ever runs once per game), same "copy at spawn instead of at INIT"
idiom etank_gen.py's own comment describes for Etank/BigZum sharing.

Both facings are generated now - "まず反転パターンを生成" - SASAPI_QUADS
(as-provided art, used while BOSS_DIR=0/moving left) and SASAPI_QUADS_L
(horizontally mirrored, used while BOSS_DIR=1/moving right). Unlike
BigZum/Flyer, which give each facing its OWN permanent pattern-code
range, both of Sasapi's facings share the SAME 64 VRAM slots
(PAT_SASAPI, still reusing BigZum's own whole footprint) - there simply
isn't a 2nd free 64-slot block anywhere in the budget for a permanent
2nd facing (see this module's own note on why 1 facing already needed
BigZum's entire range). combined_test.asm reloads whichever facing's
512 bytes are needed via LDIRVM only at the moment BOSS_DIR actually
changes (spawn, and each edge-reversal) - a few times over the whole
patrol, not every frame - rather than duplicating the VRAM footprint.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SPRITE_DIR = os.path.join(HERE, "sprites")


def _chardata_layout():
    """tools/bgm_data/bgm_bank_gen.pyがキャッシュ済みの共有"bgm-data"
    バンク(round64、BGM専用から拡張)内の、このファイルが生成する
    64x64/32x32ボス本体データの配置オフセット。mido不要(build_bank()は
    キャッシュファイルを読むだけ)。"""
    sys.path.insert(0, os.path.join(HERE, "..", "bgm_data"))
    import bgm_bank_gen as bg
    _, layout = bg.build_bank()
    return layout["SASAPI_CHARDATA"]


def sasapi_quads_raw():
    """(normal, hflipped) 64x64ボス本体パターンの生バイト列、512byte x2
    facings - emit_asm_tables()がround64まで直接DB展開していたのと
    同一のバイト列(quadrants_from_bitsの歩き順も完全に同じ)。
    tools/bgm_data/bgm_bank_gen.pyの_generate()専用(生成時にのみ
    呼ばれる、通常の実行時パスでは使わない)。"""
    bits = load_bits("Sasapi")

    def flat(b):
        out = []
        for q in quadrants_from_bits(b):
            out.extend(q)
        return bytes(out)

    return flat(bits), flat(hflip_bits(bits))


def sasapi_broken_quads_raw():
    """同じ考え方、32x32のbroken-form本体、128byte x2facings。"""
    bits = load_bits("SasapiBroken_32x32")

    def flat(b):
        out = []
        for q in quadrants_from_bits(b, size=32):
            out.extend(q)
        return bytes(out)

    return flat(bits), flat(hflip_bits(bits))

GRID = 4   # 4x4 quadrants of 16x16 = 64x64


def load_bits(name):
    return json.load(open(os.path.join(SPRITE_DIR, f"{name}.json")))["bits"]


def hflip_bits(bits):
    return [list(reversed(row)) for row in bits]


def sub8(bits, row0, col0):
    return [row[col0:col0 + 8] for row in bits[row0:row0 + 8]]


def to_bytes(tile8x8):
    out = []
    for row in tile8x8:
        b = 0
        for i, v in enumerate(row):
            if v:
                b |= (0x80 >> i)
        out.append(b)
    return out


def block16_bytes(bits, row0, col0):
    """One 16x16 sprite's 32 bytes: TL8,BL8,TR8,BR8 sub-quadrants - same
    real-hardware pattern-group byte order as bigzum_gen.py/
    flyer_gen.py's own block16_bytes."""
    tl = to_bytes(sub8(bits, row0, col0))
    bl = to_bytes(sub8(bits, row0 + 8, col0))
    tr = to_bytes(sub8(bits, row0, col0 + 8))
    br = to_bytes(sub8(bits, row0 + 8, col0 + 8))
    return tl + bl + tr + br


def quadrants_from_bits(bits, size=64):
    """Row-major walk (TL first, then rightward, then down a row) over a
    size x size sprite in 16x16 steps - BOSS_QUAD_OFFSETS/BOSS_BROKEN_
    QUAD_OFFSETS in combined_test.asm walk the same order to pair each
    quadrant's pattern group with its own on-screen Y/X delta. size=64
    (default, the 4x4/16-quadrant original body) or size=32 (round36-14
    Part C's own 2x2/4-quadrant broken body)."""
    quads = []
    for row0 in range(0, size, 16):
        for col0 in range(0, size, 16):
            quads.append(block16_bytes(bits, row0, col0))
    return quads


def db_bytes(byte_list, per_line=16):
    lines = []
    for i in range(0, len(byte_list), per_line):
        chunk = byte_list[i:i + per_line]
        lines.append("    DB " + ",".join(f"{b}" for b in chunk))
    return "\n".join(lines)


def emit_asm_tables():
    """(round64更新、"キャラクター定義データを他のバンクに逃がして
    しまえばかなり開くだろう ボスだけでもかなり空くのでは"): SASAPI_
    QUADS/_L(64x64ボス本体、512byte x2facings)は、Stage2 ROMの空き
    容量が実質枯渇していた(残り1byte)ため、ここに直接DB展開する
    従来方式から、tools/bgm_data/bgm_bank_gen.pyが管理する共有
    "bgm-data"バンク(BGM本体だけでは16KB中11KB以上が空いていた)へ
    移設した。ここではその移設先のバンク内オフセットをEQU定数として
    埋め込むだけで、実データ自体はもうこのファイルの出力(combined_
    test.asmへ埋め込まれるテキスト)には一切含まれない。実際のロードは
    combined_test.asm側のLOAD_SASAPI_PATTERNSが、ボス出現/向き反転の
    瞬間にだけwindowBを一時的にこのバンクへ切り替えてLDIRVMする
    (SWITCH_TO_CHARDATA_BANK/RESTORE_OWN_BANK_B、tools/bgm_data/
    bgm_bank_gen.pyのBGM_LOAD_SONGと全く同じ「1回だけ切替→戻す」
    パターン)。hflip_bits適用済みの64x64ビットマップを16quadrantsへ
    分割する処理自体(quadrants_from_bits)、BOSS_QUAD_OFFSETSとの対応
    関係は完全に無変更 - 生バイト列の生成場所がsasapi_quads_raw()へ
    移り、その呼び出し元がこのファイル自身からtools/bgm_data/
    bgm_bank_gen.pyの_generate()(生成時のみ)へ移っただけ。"""
    layout = _chardata_layout()
    out = ["; ===== Sasapi (boss) sprite pattern DATA moved to the shared bgm-data bank "
           "(round64, tools/bgm_data/bgm_bank_gen.py) - these are now just bank-relative "
           "byte offsets, see LOAD_SASAPI_PATTERNS in combined_test.asm ====="]
    out.append(f"SASAPI_QUADS EQU {layout['SASAPI_QUADS']}")
    out.append(f"SASAPI_QUADS_L EQU {layout['SASAPI_QUADS_L']}")
    out.append(emit_broken_asm_tables())
    out.append(emit_broken_path_tables())
    out.append(emit_broken_beam_asm_tables())
    return "\n".join(out)


# ---------- round36-14 Part C: broken form (32x32, 2x2 quadrants) ----------
def emit_broken_asm_tables():
    """emit_asm_tables()と同じround64の移設(こちらは32x32/128byte
    x2facings)。sasapi_broken_quads_raw()がtools/bgm_data/
    bgm_bank_gen.pyの_generate()から呼ばれ、共有バンクへ実際のバイト
    列を書き込む - ここでは移設先オフセットのEQUを埋め込むだけ。"""
    layout = _chardata_layout()
    out = ["; ===== Sasapi broken-form (32x32) sprite pattern DATA moved to the shared "
           "bgm-data bank (round64), see SASAPI_QUADS' own comment ====="]
    out.append(f"SASAPI_BROKEN_QUADS EQU {layout['SASAPI_BROKEN_QUADS']}")
    out.append(f"SASAPI_BROKEN_QUADS_L EQU {layout['SASAPI_BROKEN_QUADS_L']}")
    return "\n".join(out)


# round36-14 follow-up #4 ("停止中にビーム攻撃をする 添付がそのキャラ
# データ...角度は絵から判断") - 4 genuinely distinct 16x16 diagonal-beam
# tiles (not a mirror pair like SASAPI_QUADS/_L, and not an 8x8-lit-in-
# a-16x16-canvas trick like sbeam_gen.py's own single SBEAM_SPRITE - all
# 4 use their own full 16x16 canvas). quadrants_from_bits(bits, size=16)
# walks exactly ONE 16x16 quadrant (range(0,16,16) has a single step),
# giving the same 32-byte TL/BL/TR/BR layout a real hw sprite pattern
# needs, reusing the existing helper rather than duplicating sbeam_
# gen.py's own single-purpose 8x8 packer.
def emit_broken_beam_asm_tables():
    out = ["; ===== Sasapi broken-form beam-attack sprite patterns: generated by sasapi_gen.py, do not hand-edit ====="]
    for n in (1, 2, 3, 4):
        bits = load_bits(f"SBeam{n}_16x16")
        out.append(f"BOSS_BROKEN_BEAM{n}_SPRITE:")
        out.append(db_bytes(quadrants_from_bits(bits, size=16)[0]))
    return "\n".join(out)


# figure-8 (Gerono lemniscate) path LUT for the broken form's own
# "インフィニティの起動で画面を移動" drift - x(t)=CX+AX*cos(t),
# y(t)=CY+AY*sin(t)*cos(t) for t in [0,2*pi), BOSS_BROKEN_PATH_LEN
# samples. A plain sin/cos parametric curve rather than any in-engine
# trig (Z80 has no FPU/multiply and this file has no existing sine
# table) - precomputed once here, walked as a flat byte LUT at runtime
# (UPDATE_BOSS_BROKEN_ACTIVE), same "generator script produces the
# table, hand-written asm just walks it" split as every other LUT in
# this codebase (BOSS_EXPL_FLIGHT_TABLE, BOSS_QUAD_OFFSETS, etc).
# BOSS_BROKEN_PATH_LEN is a power of 2 (64) on purpose - the asm side
# derives its own table index as a plain AND against GAME_TICK's own low
# byte, no division/modulo needed.
#
# round36-14 follow-up #1 (real-hardware report: "スパーク爆発後ボスの
# 爆発位置に関係なく右から出てきてる 爆発位置からでなきゃおかしい") -
# briefly rewritten as offsets from a per-death origin instead of this
# fixed center, but that produced a NEW complaint (follow-up #2:
# "インフィニティ軌道はその位置から始まるが一旦中央に寄せろ センタリン
# グするかたちで 今だと端で倒すと画面半分の狭い起動で動いてしまってる")
# - clamping the origin near a screen edge made the visible loop lopsided
# and cramped there. Settled design: the body still visibly APPEARS at
# the real death position (combined_test.asm's own TRIGGER_BOSS_BROKEN_
# FORM captures nothing new for this any more - BOSS_X/BOSS_Y already
# hold it), then a new RECENTERING sub-phase (UPDATE_BOSS_BROKEN_ACTIVE)
# walks it toward THIS fixed center before the loop itself starts - so
# the loop table here goes back to being plain absolute coordinates
# around one constant, always-safe center, same as the very first
# attempt, just reached via a visible transition instead of instantly.
# CX/CY/AX/AY chosen so the whole 32x32 sprite stays clear of the HUD
# (top rows) and the terrain's own scrolling band (BULLET_ROCK_ROW_MIN*
# 8=128) at every sample - X in [48,176], Y in [48,112], both
# comfortably inside 0-223/0-191 for a 32px sprite on a 256x192 screen.
# Untuned initial placeholder (like BOSS_BROKEN_MOVE_MIN_TICKS' own
# comment) - pacing/shape is not yet tuned against real gameplay.
# (2026-09-06、実機フィードバック対応: "位置が低いので16Px上に戻るように"
# -元々のCY=80から16px上のCY=64へ変更。振幅AY=32は無変更のためY範囲は
# [48,112]→[32,96]へ平行移動するだけで、HUD帯(row0)・地形スクロール帯
# (row16以降=128px)双方から引き続き十分に離れている。)
BOSS_BROKEN_PATH_LEN = 64
_PATH_CX, _PATH_CY = 112, 64
_PATH_AX, _PATH_AY = 64, 32


def broken_path_samples():
    xs, ys = [], []
    for i in range(BOSS_BROKEN_PATH_LEN):
        t = 2 * math.pi * i / BOSS_BROKEN_PATH_LEN
        xs.append(int(round(_PATH_CX + _PATH_AX * math.cos(t))))
        ys.append(int(round(_PATH_CY + _PATH_AY * math.sin(t) * math.cos(t))))
    return xs, ys


def emit_broken_path_tables():
    """BOSS_BROKEN_PATH_X/_Y (the sampled ABSOLUTE position at each of
    the 64 points, centered on the fixed BOSS_BROKEN_CENTER_X/Y) plus
    BOSS_BROKEN_PATH_DIR (1=this step's own X is moving right vs the
    next sample, 0=left - same BOSS_DIR convention UPDATE_BOSS_BROKEN_
    ACTIVE picks SASAPI_BROKEN_QUADS/_L with), precomputed here rather
    than derived from a live delta at runtime - one less runtime
    comparison, and avoids any ambiguity at the 2 stationary turning
    points (dx=0) since the LUT just states the intended facing directly
    instead of inferring it from a delta that can legitimately be
    exactly 0 there. Also emits BOSS_BROKEN_PATH_CROSS_INDEX - the one
    index where the loop passes exactly through its own center (t=pi/2,
    a quarter of the way around) - UPDATE_BOSS_BROKEN_ACTIVE's own
    RECENTERING sub-phase starts the orbit there so the hand-off from
    "walked to the center" to "now orbiting" has no visible jump."""
    xs, ys = broken_path_samples()
    dirs = [1 if xs[(i + 1) % BOSS_BROKEN_PATH_LEN] >= xs[i] else 0 for i in range(BOSS_BROKEN_PATH_LEN)]
    out = [
        "; ===== Sasapi broken-form figure-8 path LUT: generated by sasapi_gen.py, do not hand-edit =====",
        f"BOSS_BROKEN_PATH_LEN EQU {BOSS_BROKEN_PATH_LEN}",
        f"BOSS_BROKEN_CENTER_X EQU {_PATH_CX}",
        f"BOSS_BROKEN_CENTER_Y EQU {_PATH_CY}",
        f"BOSS_BROKEN_PATH_CROSS_INDEX EQU {BOSS_BROKEN_PATH_LEN // 4}",
        "BOSS_BROKEN_PATH_X:",
        db_bytes(xs),
        "BOSS_BROKEN_PATH_Y:",
        db_bytes(ys),
        "BOSS_BROKEN_PATH_DIR:",
        db_bytes(dirs),
    ]
    return "\n".join(out)


if __name__ == "__main__":
    print("Sasapi converted, 16x32 bytes x2 facings")
    tables_path = os.path.join(HERE, "sasapi_tables.inc.asm")
    with open(tables_path, "w") as f:
        f.write(emit_asm_tables())
    print("wrote", tables_path)
