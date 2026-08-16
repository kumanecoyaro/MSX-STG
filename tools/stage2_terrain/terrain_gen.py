"""Generates the Stage-2 4-row connected ground/slope scroller: pattern
data (steady + phase-blended transition tiles), the 4 parallel per-row
ROWDATA-style id maps for a test track (climb 4 tiers, descend 4 tiers,
loop), and the id/PAIRBASE/SOLOTAB tables - reusing stage 1's exact
REFRESH_IDCACHE_33 / CELL_LOOP / PAIRBASE-blend engine (see
tools/bankswitch_poc's stage2 notes), but with all 4 rows sharing ONE
PXCHAR/PHASE clock (gated every 8 ticks, same as stage1's fastest tier
G8) instead of stage1's 4 independently-rated parallax tiers - this is
one physically connected surface, not independent decorative layers.

Tile art source: two 16x16 sprites from the Sprite Editor -
Rock.json (flat ground, content only in the top 8 rows = one 16x8
tile pair) and Rock225.json (the climb transition: upper 8 rows =
the rising diagonal edge, lower 8 rows = the "filled in" ground it
leaves behind). The descend transition reuses Rock225 mirrored
left-right (per direct instruction: generate the down-slope by
flipping the up-slope, not drawing a new sprite).

Phase-blend tiles (the "how it looks 1-7 pixels into the scroll"
frames PAIRBASE needs) are synthesized programmatically by horizontal
bit-shift-and-OR between the two tiles of a transition, rather than
hand-drawn - this is a pure per-pixel horizontal translation, exactly
what smooth left-scroll looks like, so it doesn't need new art.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SPRITE_DIR = os.path.join(HERE, "sprites")


def load_bits(name):
    return json.load(open(os.path.join(SPRITE_DIR, f"{name}.json")))["bits"]


def sub_tile(bits, row0, col0):
    return [row[col0:col0 + 8] for row in bits[row0:row0 + 8]]


def hflip(tile8x8):
    return [list(reversed(row)) for row in tile8x8]


def to_bytes(tile8x8):
    out = []
    for row in tile8x8:
        b = 0
        for i, v in enumerate(row):
            if v:
                b |= (0x80 >> i)
        out.append(b)
    return out


def blend(tile_a, tile_b, phase):
    """8x8 tile showing tile_a shifted phase(0-7) pixels left, with
    tile_b's leftmost `phase` columns sliding in on the right - the
    exact appearance of the boundary between cell A and cell B after
    scrolling the view `phase` pixels to the left."""
    out = []
    for ra, rb in zip(tile_a, tile_b):
        byte_a = 0
        for i, v in enumerate(ra):
            if v:
                byte_a |= (0x80 >> i)
        byte_b = 0
        for i, v in enumerate(rb):
            if v:
                byte_b |= (0x80 >> i)
        if phase == 0:
            out.append(byte_a)
        else:
            shifted = ((byte_a << phase) | (byte_b >> (8 - phase))) & 0xFF
            out.append(shifted)
    return out


# ---------- load + split the two sprites ----------
rock = load_bits("Rock")
r225 = load_bits("Rock225")

ROCK_L = sub_tile(rock, 0, 0)
ROCK_R = sub_tile(rock, 0, 8)
R225_UL = sub_tile(r225, 0, 0)
R225_UR = sub_tile(r225, 0, 8)
R225_LL = sub_tile(r225, 8, 0)
R225_LR = sub_tile(r225, 8, 8)
R225D_UL = hflip(R225_UR)
R225D_UR = hflip(R225_UL)
R225D_LL = hflip(R225_LR)
R225D_LR = hflip(R225_LL)
BLANK = [[0] * 8 for _ in range(8)]

# ---------- id table ----------
ID_NAMES = ["BLANK", "ROCK_L", "ROCK_R", "R225_UL", "R225_UR", "R225_LL",
            "R225_LR", "R225D_UL", "R225D_UR", "R225D_LL", "R225D_LR"]
ID_TILES = [BLANK, ROCK_L, ROCK_R, R225_UL, R225_UR, R225_LL,
            R225_LR, R225D_UL, R225D_UR, R225D_LL, R225D_LR]
N_IDS = len(ID_NAMES)
BLANK_ID, ROCK_L_ID, ROCK_R_ID = 0, 1, 2
R225_UL_ID, R225_UR_ID, R225_LL_ID, R225_LR_ID = 3, 4, 5, 6
R225D_UL_ID, R225D_UR_ID, R225D_LL_ID, R225D_LR_ID = 7, 8, 9, 10


# ---------- build the 4-row test track (climb 4, descend 4, loop) ----------
def build_track():
    rows = [[], [], [], []]  # row index 0=top(row20) .. 3=bottom(row23)
    tier = 0

    def ground_i(t):
        return 3 - t

    def emit_flat(n):
        gi = ground_i(tier)
        for k in range(n):
            for i in range(4):
                if i > gi:
                    rows[i].append(ROCK_L_ID if k % 2 == 0 else ROCK_R_ID)
                elif i == gi:
                    rows[i].append(ROCK_L_ID if k % 2 == 0 else ROCK_R_ID)
                else:
                    rows[i].append(BLANK_ID)

    def emit_climb():
        nonlocal tier
        gi = ground_i(tier)
        new_gi = gi - 1
        for k, (lo, up) in enumerate([(R225_LL_ID, R225_UL_ID), (R225_LR_ID, R225_UR_ID)]):
            for i in range(4):
                if i > gi:
                    rows[i].append(ROCK_L_ID if k % 2 == 0 else ROCK_R_ID)
                elif i == gi:
                    rows[i].append(lo)
                elif i == new_gi:
                    rows[i].append(up)
                else:
                    rows[i].append(BLANK_ID)
        tier += 1

    def emit_descend():
        nonlocal tier
        gi = ground_i(tier)
        new_gi = gi + 1
        for k, (lo, up) in enumerate([(R225D_LL_ID, R225D_UL_ID), (R225D_LR_ID, R225D_UR_ID)]):
            for i in range(4):
                if i > new_gi:
                    rows[i].append(ROCK_L_ID if k % 2 == 0 else ROCK_R_ID)
                elif i == new_gi:
                    rows[i].append(lo)
                elif i == gi:
                    rows[i].append(up)
                else:
                    rows[i].append(BLANK_ID)
        tier -= 1

    FLAT_RUN = 24
    for _ in range(4):
        emit_flat(FLAT_RUN)
        emit_climb()
    emit_flat(FLAT_RUN)
    for _ in range(4):
        emit_flat(FLAT_RUN)
        emit_descend()
    emit_flat(FLAT_RUN)
    assert tier == 0
    return rows


ROWS = build_track()
TRACK_LEN = len(ROWS[0])
for r in ROWS:
    assert len(r) == TRACK_LEN

# ---------- collect every (curr,next) pair that actually occurs, ----------
# including the wraparound pair (last cell -> first cell), across all 4 rows
PAIRS = set()
for r in ROWS:
    for k in range(TRACK_LEN):
        curr = r[k]
        nxt = r[(k + 1) % TRACK_LEN]
        PAIRS.add((curr, nxt))


# ---------- character code assignment ----------
# BLANK (id0) is alone in group0 (codes 0-7, only code0 used) so it can
# have its own sky color, independent of the rock/slope codes' color -
# a color group is 8 CONSECUTIVE codes sharing one fg/bg byte, so
# packing BLANK into the same group as rock codes (as the very first
# version of this did) would force them to share one color.
# codes 8-17: steady-state tile per id 1-10 (SOLOTAB below maps id->code)
# codes 24+: 7-frame (phase 1-7) blend sequences, one block per pair,
# in a fixed order so PAIRBASE[curr*N_IDS+next] can point at the block start.
BLANK_CODE = 0
STEADY_BASE = 8   # ids 1..10 -> codes 8..17
BLEND_BASE = 24    # next group-aligned boundary after 8+10=18

STEADY_CODE = [BLANK_CODE] + [STEADY_BASE + i for i in range(N_IDS - 1)]

PAIR_LIST = sorted(PAIRS)
PAIR_INDEX = {p: i for i, p in enumerate(PAIR_LIST)}


def pair_block_code(pair):
    return BLEND_BASE + PAIR_INDEX[pair] * 7


def build_pattern_table():
    """code -> 8 bytes. Returns (patterns dict, highest code used)."""
    patterns = {}
    for idx, tile in enumerate(ID_TILES):
        patterns[STEADY_CODE[idx]] = to_bytes(tile)
    for pair in PAIR_LIST:
        curr, nxt = pair
        base = pair_block_code(pair)
        for phase in range(1, 8):
            patterns[base + phase - 1] = blend(ID_TILES[curr], ID_TILES[nxt], phase)
    return patterns


PATTERNS = build_pattern_table()
MAX_CODE = max(PATTERNS)

MUL_N = [i * N_IDS for i in range(N_IDS)]
SOLOTAB = STEADY_CODE
PAIRBASE = [0] * (N_IDS * N_IDS)
for pair in PAIR_LIST:
    curr, nxt = pair
    PAIRBASE[curr * N_IDS + nxt] = pair_block_code(pair)

# ---------- color table ----------
# group0 (codes 0-7, BLANK's group) = sky: light blue on light blue
# (BLANK's pattern is all-0 so only bg would ever show, but set both
# nibbles the same for a clean solid fill regardless).
# groups covering codes 8.. (rock/slope/blend) = fg unchanged from the
# source sprites (8 = medium red), bg = dark yellow (per direct
# instruction: keep the current reddish color, change the other one to
# light red or dark yellow - dark yellow reads more like natural
# rock/dirt, easy to flip to light red (9) if that reads better).
SKY_COLOR = 0x55           # fg=5,bg=5 (light blue)
ROCK_COLOR = 0x8A          # fg=8 (medium red, unchanged), bg=10 (dark yellow)
N_COLOR_GROUPS = 32
COLORDATA = [SKY_COLOR] + [ROCK_COLOR] * (N_COLOR_GROUPS - 1)

WRAP_PAD = 33
ROWDATA_PADDED = [r + r[:WRAP_PAD] for r in ROWS]


def db_bytes(byte_list, per_line=16):
    lines = []
    for i in range(0, len(byte_list), per_line):
        chunk = byte_list[i:i + per_line]
        lines.append("    DB " + ",".join(f"{b}" for b in chunk))
    return "\n".join(lines)


def emit_asm_tables():
    out = []
    out.append("; ===== Stage2 terrain test: generated by terrain_gen.py, do not hand-edit =====")
    out.append(f"TERRAIN_N_IDS EQU {N_IDS}")
    out.append(f"TERRAIN_TRACK_LEN EQU {TRACK_LEN}")
    out.append("")
    out.append("    ALIGN 256")
    out.append("TERRAIN_MUL_N:")
    out.append(db_bytes(MUL_N))
    out.append("")
    out.append("    ALIGN 256")
    out.append("TERRAIN_SOLOTAB:")
    out.append(db_bytes(SOLOTAB))
    out.append("")
    out.append("    ALIGN 256")
    out.append("TERRAIN_PAIRBASE:")
    out.append(db_bytes(PAIRBASE))
    out.append("")
    for i in range(4):
        out.append(f"TERRAIN_ROWDATA{i}:")
        out.append(db_bytes(ROWDATA_PADDED[i]))
        out.append("")
    out.append("TERRAIN_PATTERNS:")
    for code in range(MAX_CODE + 1):
        bytes_ = PATTERNS.get(code, [0] * 8)
        out.append(f"    DB " + ",".join(f"{b}" for b in bytes_) + f"  ; code {code}")
    out.append(f"TERRAIN_PATTERN_COUNT EQU {MAX_CODE + 1}")
    out.append("")
    out.append("TERRAIN_COLORDATA:")
    out.append(db_bytes(COLORDATA))
    return "\n".join(out)


if __name__ == "__main__":
    print(f"track length: {TRACK_LEN} cells")
    print(f"distinct (curr,next) pairs used: {len(PAIRS)}")
    print(f"pattern codes used: 0-{MAX_CODE} ({MAX_CODE+1} total)")
    tables_path = os.path.join(HERE, "terrain_tables.inc.asm")
    with open(tables_path, "w") as f:
        f.write(emit_asm_tables())
    print("wrote", tables_path)
