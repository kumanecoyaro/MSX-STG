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

HERE = os.path.dirname(os.path.abspath(__file__))
SPRITE_DIR = os.path.join(HERE, "sprites")

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
    """16 quadrants x 32 bytes (TL,BL,TR,BR sub-patterns) = 512 bytes per
    facing, laid out contiguously in on-screen quadrant order under one
    label per facing - combined_test.asm loads whichever one is needed
    with a single 512-byte LDIRVM into PAT_BIGZUM*8 (reused - see this
    module's own docstring), since both source and destination are
    already contiguous. hflip_bits is applied to the whole 64x64 bitmap
    BEFORE slicing into quadrants, not to each quadrant's own bytes
    after - this correctly handles both the per-pixel mirror AND the
    quadrant repositioning (a mirrored image's own top-left quadrant is
    the mirrored content of the ORIGINAL's top-right one) in one step,
    while BOSS_QUAD_OFFSETS' fixed on-screen positions stay unchanged
    either way. No EQU base emitted here since the destination is
    decided in combined_test.asm, not by this file."""
    bits = load_bits("Sasapi")
    out = ["; ===== Sasapi (boss) sprite patterns: generated by sasapi_gen.py, do not hand-edit ====="]
    for label, b in [("SASAPI_QUADS", bits), ("SASAPI_QUADS_L", hflip_bits(bits))]:
        out.append(f"{label}:")
        for q in quadrants_from_bits(b):
            out.append(db_bytes(q))
    out.append(emit_broken_asm_tables())
    out.append(emit_broken_path_tables())
    return "\n".join(out)


# ---------- round36-14 Part C: broken form (32x32, 2x2 quadrants) ----------
def emit_broken_asm_tables():
    """Same TL/BL/TR/BR-per-16x16-quadrant approach as the 64x64 body
    above, just a 2x2 grid (4 quadrants) instead of 4x4 - see
    quadrants_from_bits' own size= parameter. sprites/
    SasapiBroken_32x32.json (user-attached, round36-14) uses the exact
    same {width,height,fg,bg,bits} schema load_bits already expects, so
    it loads unmodified."""
    bits = load_bits("SasapiBroken_32x32")
    out = ["; ===== Sasapi broken-form (32x32) sprite patterns: generated by sasapi_gen.py, do not hand-edit ====="]
    for label, b in [("SASAPI_BROKEN_QUADS", bits), ("SASAPI_BROKEN_QUADS_L", hflip_bits(bits))]:
        out.append(f"{label}:")
        for q in quadrants_from_bits(b, size=32):
            out.append(db_bytes(q))
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
# byte, no division/modulo needed. Center/amplitude chosen so the whole
# 32x32 sprite stays clear of the HUD (top rows) and the terrain's own
# scrolling band (BULLET_ROCK_ROW_MIN*8=128) at every sample - X in
# [16,208], Y in [36,124], both comfortably inside 0-223/0-191 for a
# 32px-wide/tall sprite on a 256x192 screen. Untuned initial placeholder
# (like BOSS_BROKEN_MOVE_MIN_TICKS' own comment) - pacing/shape is not
# yet tuned against real gameplay.
BOSS_BROKEN_PATH_LEN = 64
_PATH_CX, _PATH_CY = 112, 80
_PATH_AX, _PATH_AY = 96, 88


def broken_path_samples():
    xs, ys = [], []
    for i in range(BOSS_BROKEN_PATH_LEN):
        t = 2 * math.pi * i / BOSS_BROKEN_PATH_LEN
        xs.append(int(round(_PATH_CX + _PATH_AX * math.cos(t))))
        ys.append(int(round(_PATH_CY + _PATH_AY * math.sin(t) * math.cos(t))))
    return xs, ys


def emit_broken_path_tables():
    """BOSS_BROKEN_PATH_X/_Y (the sampled position at each of the 64
    points) plus BOSS_BROKEN_PATH_DIR (1=this step's own X is moving
    right vs the next sample, 0=left - same BOSS_DIR convention
    UPDATE_BOSS_BROKEN_ACTIVE picks SASAPI_BROKEN_QUADS/_L with),
    precomputed here rather than derived from a live X delta at runtime -
    one less runtime comparison, and avoids any ambiguity at the 2
    stationary turning points (dx=0) since the LUT just states the
    intended facing directly instead of inferring it from a delta that
    can legitimately be exactly 0 there."""
    xs, ys = broken_path_samples()
    dirs = [1 if xs[(i + 1) % BOSS_BROKEN_PATH_LEN] >= xs[i] else 0 for i in range(BOSS_BROKEN_PATH_LEN)]
    out = [
        "; ===== Sasapi broken-form figure-8 path LUT: generated by sasapi_gen.py, do not hand-edit =====",
        f"BOSS_BROKEN_PATH_LEN EQU {BOSS_BROKEN_PATH_LEN}",
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
