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
# Both Rock and Rock225 only use their own top 16x8 half (one row, 2
# cells) - the bottom half of each source JSON is unused (confirmed
# per direct instruction). Rock225's marker appears exactly once, in
# whichever row is newly becoming rock (or newly becoming open air,
# on the way down) - it does NOT get a second, duplicate placement in
# the row below/above it. Placing R225's own bottom half there too (an
# earlier version of this did) put two markers at the same columns in
# two different rows instead of one marker per row at its own correct
# moment - that's the reported horizontal misalignment.
rock = load_bits("Rock")
r225 = load_bits("Rock225")

ROCK_L = sub_tile(rock, 0, 0)
ROCK_R = sub_tile(rock, 0, 8)
R225_UL = sub_tile(r225, 0, 0)
R225_UR = sub_tile(r225, 0, 8)
R225D_UL = hflip(R225_UR)
R225D_UR = hflip(R225_UL)
# id0/BLANK ("not yet grown into rock" cells within the scrolling band -
# see the character-code-assignment comment below) used to be a flat
# solid-color tile (all-zero bits, so only the group's own bg showed) -
# given actual texture per direct instruction: "Rockの左右のイエロー
# ブランクにSandを設定" (put Sand in the yellow blanks to the left/
# right of Rock). Sand.json's own fg/bg are ignored - like every other
# tile here, it just contributes bits; the uniform ROCK_COLOR group
# still supplies the actual color (see COLORDATA below), same as
# ROCK_L/ROCK_R's own fg/bg from Rock.json are ignored too.
BLANK = load_bits("Sand")
BLANK_FLAT = [[0] * 8 for _ in range(8)]  # see _blend_tile() below

# ---------- id table ----------
ID_NAMES = ["BLANK", "ROCK_L", "ROCK_R", "R225_UL", "R225_UR", "R225D_UL", "R225D_UR"]
ID_TILES = [BLANK, ROCK_L, ROCK_R, R225_UL, R225_UR, R225D_UL, R225D_UR]
N_IDS = len(ID_NAMES)
BLANK_ID, ROCK_L_ID, ROCK_R_ID = 0, 1, 2
R225_UL_ID, R225_UR_ID = 3, 4
R225D_UL_ID, R225D_UR_ID = 5, 6


# ---------- build the 4-row test track (climb, descend, loop) ----------
def build_track():
    rows = [[], [], [], []]  # row index 0=top(row20) .. 3=bottom(row23)
    tier = 0

    def ground_i(t):
        assert 0 <= t <= 3, f"tier {t} out of range - only 4 rows (20-23) exist, 3 climbs/descends max"
        return 3 - t

    def emit_flat(n):
        gi = ground_i(tier)
        for k in range(n):
            for i in range(4):
                rows[i].append((ROCK_L_ID if k % 2 == 0 else ROCK_R_ID) if i >= gi else BLANK_ID)

    def emit_climb():
        # The Rock225 marker appears exactly once, in the row that's
        # newly becoming rock (new_gi) - the row it climbs FROM (gi)
        # already made its own transition earlier and stays ordinary
        # flat rock here, not a second marker. Placing one in both rows
        # at the same columns (an earlier version of this did) put two
        # markers where only one belongs - reported as misaligned.
        nonlocal tier
        gi = ground_i(tier)
        new_gi = gi - 1
        for k, up in enumerate([R225_UL_ID, R225_UR_ID]):
            for i in range(4):
                if i >= gi:
                    rows[i].append(ROCK_L_ID if k % 2 == 0 else ROCK_R_ID)
                elif i == new_gi:
                    rows[i].append(up)
                else:
                    rows[i].append(BLANK_ID)
        tier += 1

    def emit_descend():
        # Mirror of emit_climb: the marker appears once, in the row
        # that's newly becoming open air again (gi, the row being
        # abandoned) - new_gi (one row further down) was already
        # ordinary flat rock and stays that way, unaffected.
        nonlocal tier
        gi = ground_i(tier)
        new_gi = gi + 1
        for k, down in enumerate([R225D_UL_ID, R225D_UR_ID]):
            for i in range(4):
                if i >= new_gi:
                    rows[i].append(ROCK_L_ID if k % 2 == 0 else ROCK_R_ID)
                elif i == gi:
                    rows[i].append(down)
                else:
                    rows[i].append(BLANK_ID)
        tier -= 1

    # Only 4 rows (20-23 = tiers 0-3) exist, so reaching the top from
    # the bottom - or the bottom from the top - takes exactly 3 climb/
    # descend transitions, not 4 (a "4-tier slope" means 4 distinct
    # height LEVELS, i.e. 3 steps between them - the same off-by-one
    # every staircase has). A 4th call used to silently try tier 4,
    # which doesn't exist - ground_i() now asserts on that instead of
    # quietly corrupting the row past that point.
    FLAT_RUN = 24
    for _ in range(3):
        emit_flat(FLAT_RUN)
        emit_climb()
    emit_flat(FLAT_RUN)
    # Extra flat cells merged into the tier-3 apex run above (still tier
    # 3, no transition between this and the emit_flat(FLAT_RUN) just
    # before or the loop's own first emit_flat(FLAT_RUN) just after -
    # same "no transition = one continuous run" mechanic that already
    # produces the existing 48-cell/384px apex run) - a slow ground
    # enemy that doesn't elevation-follow terrain at all (Etank) needs
    # to stay on flat ground for its *entire* crossing, not just at
    # spawn, so the flat window has to outlast its full on-screen
    # lifetime plus however far the terrain itself scrolls meanwhile -
    # "地形上り下りはしないので長い平地のみスポーン 合わせて通過に
    # 必要な長い平地を設置". Widened well past the original 384px with
    # margin (44 extra cells = 352px, total run now 92 cells = 736px,
    # since it also merges with the descend loop's own leading
    # emit_flat(FLAT_RUN) right after this call, still tier 3 - verified
    # directly: the row0-solid steady-flat run spans columns 78-169,
    # 92 cells) rather than cutting it close.
    emit_flat(44)
    for _ in range(3):
        emit_flat(FLAT_RUN)
        emit_descend()
    emit_flat(FLAT_RUN)

    # Rapid back-to-back climb: all 3 transitions (0->1->2->3) chained
    # with no flat run in between - this is the actual point of using a
    # shallow 22.5-degree per-tier slope instead of a steep 45-degree
    # one: chaining them directly still reads as one continuous
    # climbable ramp instead of a sheer wall. Then the same going down.
    #
    # This is the ONLY other tier-3(apex)/row0-solid stretch in the
    # whole track besides the widened run above - Etank's own spawn
    # gate (ETANK_TERRAIN_OK in combined_test.asm) can only probe
    # "is the currently-visible surface tier 0 (topmost/apex)" at
    # runtime, with no way to tell which of the 2 occurrences it's
    # looking at, so leaving this one at the original short FLAT_RUN
    # (24 cells/192px) would let Etank spawn here too and run out of
    # matching flat ground mid-crossing exactly the way the widened
    # run above was fixing. Widened to the same 92-cell length as that
    # run instead of a fresh, differently-tuned number, so both tier-3
    # windows carry equal safety margin.
    for _ in range(3):
        emit_climb()
    emit_flat(92)
    for _ in range(3):
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
# id0 (BLANK, now Sand-textured - see the BLANK= assignment above) is
# used within build_track() for "not yet reached by Rock" cells INSIDE
# the scrolling 4-row band - conceptually still rock territory, just
# without texture grown in yet, so historically it shared Rock's own
# code range (and therefore its color) rather than the sky's. That
# stayed true even once it got real Sand art - until "Sandの文字色を
# ダークイエローに" needed Sand's own fg independent of Rock's, which
# SCREEN1 can't do while packed into the same 8-code color group.
#
# The true, permanently-open sky ABOVE the whole terrain band (rows
# outside it entirely, cleared once at INIT - see TERRAIN_BLANK_ROW in
# terrain_test.asm) is a completely separate, dedicated code
# (SKY_BLANK_CODE=0, its own group0/sky color) that this id/pattern
# system never touches - it's a static one-time fill, not part of the
# scrolling map, so it doesn't go through PAIRBASE/blending at all.
SKY_BLANK_CODE = 0
STEADY_BASE = 8     # ROCK_L..R225D_UR (ids1-6) -> codes8-13, all rock-colored
BLANK_CODE = 16     # id0/Sand's own dedicated code/color group (2) - see BLANK_PAIR_BASE below for BLEND_BASE

STEADY_CODE = [BLANK_CODE] + [STEADY_BASE + i for i in range(N_IDS - 1)]

# Every pair gets a normal 7-frame block via the same PAIRBASE+
# ({phase}-1) formula CELL_LOOP always uses. Fine for pairs where
# NEITHER side is BLANK (still all uniformly rock-colored, so which
# exact code the phase offset lands on doesn't matter for color), but
# a *steady*, non-transitioning run of BLANK cells needs its own
# dedicated group - "Sandがチラついてるし色変わってないぞ ８キャラ分
# 変更だぞ": a cell sitting still on Sand still cycles every frame
# through the (BLANK,BLANK) same-id pair's 7 blend phases (PXCHAR
# keeps advancing even for a same-id "transition"), so if that pair's
# frames aren't sand-colored too, the one physical screen cell visibly
# flickers between sand color and whatever the pair landed on, 7
# frames out of 8.
#
# The genuinely *mixed* pairs (BLANK<->Rock/R225 - the actual climb/
# descend edge at Sand's own border) do NOT need their own dedicated
# group, and an earlier round giving them one anyway ("まだチラつい
# てる Rockの前後だけおかしい") turned out to be the wrong fix and a
# new bug in its own right - it painted the R225 diagonal marker with
# Sand's own dark-yellow fg, which barely shows up against Sand's own
# light-yellow bg ("Rock225の背景色がダークイエローだからチラついてる
# 上に一部が欠けてる"). What actually needed to change was simpler:
# once Rock's own bg became light yellow too, matching Rock225/Sand
# ("カラーグループ節約するから Rockも背景色ライトイエローにしろ
# Rock225と同じだ"), every mixed pair is free to stay in the ordinary
# rock-colored pool - no bg seam against neighboring Sand cells either
# way, and the diagonal edge keeps reading in Rock's own (higher-
# contrast, red-on-light-yellow) fg instead of sand-on-sand. So only
# the same-id (BLANK,BLANK) pair gets carved out; BLEND_BASE (the
# start of the remaining, ordinary rock-colored pairs) starts right
# after BLANK_CODE's own group2.
_self_pair = (BLANK_ID, BLANK_ID)
BLANK_PAIR_BASE = {_self_pair: BLANK_CODE + 1}
SAND_GROUPS = [BLANK_CODE // 8]
BLEND_BASE = BLANK_CODE + 8  # right after BLANK_CODE's own group2

PAIR_LIST = sorted(PAIRS - set(BLANK_PAIR_BASE))
PAIR_INDEX = {p: i for i, p in enumerate(PAIR_LIST)}


def pair_block_code(pair):
    if pair in BLANK_PAIR_BASE:
        return BLANK_PAIR_BASE[pair]
    return BLEND_BASE + PAIR_INDEX[pair] * 7


# Mixed pairs blend the real Sand tile against Rock/R225 under one
# ROCK_COLOR - Sand's speckle bits then show up red mid-scroll
# ("Rock225の前後にゴミ出てんだよ"). Fix: use a flat placeholder for
# BLANK's side in mixed pairs only; steady Sand keeps its real texture.
def _blend_tile(id_, is_mixed_pair):
    if is_mixed_pair and id_ == BLANK_ID:
        return BLANK_FLAT
    return ID_TILES[id_]


def build_pattern_table():
    """code -> 8 bytes. Returns (patterns dict, highest code used)."""
    patterns = {SKY_BLANK_CODE: to_bytes(BLANK)}
    for idx, tile in enumerate(ID_TILES):
        patterns[STEADY_CODE[idx]] = to_bytes(tile)
    for pair in sorted(PAIRS):
        curr, nxt = pair
        is_mixed = BLANK_ID in pair and pair != _self_pair
        tile_a = _blend_tile(curr, is_mixed)
        tile_b = _blend_tile(nxt, is_mixed)
        base = pair_block_code(pair)
        for phase in range(1, 8):
            patterns[base + phase - 1] = blend(tile_a, tile_b, phase)
    return patterns


PATTERNS = build_pattern_table()
MAX_CODE = max(PATTERNS)

MUL_N = [i * N_IDS for i in range(N_IDS)]
SOLOTAB = STEADY_CODE
PAIRBASE = [0] * (N_IDS * N_IDS)
for pair in PAIRS:
    curr, nxt = pair
    PAIRBASE[curr * N_IDS + nxt] = pair_block_code(pair)

# ---------- color table ----------
# group0 (SKY_BLANK_CODE=0 only) = sky: light blue on light blue
# (SKY_BLANK's pattern is all-0 so only bg would ever show, but set
# both nibbles the same for a clean solid fill regardless).
# every other group (codes 8+ - the scrolling map's rock/R225/blend
# content, including the mixed BLANK<->Rock/R225 transition pairs) =
# fg unchanged from the source sprites (8 = medium red), bg = LIGHT
# yellow (11). Originally dark yellow (10); changed to match Rock225
# and Sand's own bg exactly - "Rock225の背景色がダークイエローだから
# チラついてる...Rock225の背景色ライトイエローにしろ", then widened
# to plain Rock too rather than giving Rock225 its own separate color
# group - "カラーグループ節約するから Rockも背景色ライトイエローにし
# ろ Rock225と同じだ". Since Rock/R225/the mixed transition pairs all
# share one bg now, there's no seam anywhere except at the one
# genuinely different fg (Sand's), which is exactly where a dedicated
# group is actually needed - see SAND_GROUPS below.
# SAND_GROUPS (just BLANK_CODE's own group2, holding BLANK's solo tile
# and the (BLANK,BLANK) same-id blend pair - see BLANK_PAIR_BASE
# above) get their own fg/bg pair instead - "Sandは文字色ダークイエ
# ロー、背景色ライトイエローだぞ いまは多分同じ色" (fg dark yellow,
# bg LIGHT yellow - an earlier round used the same dark yellow for
# both, an actual mistake, not a deliberate "blend into the ground"
# choice).
SKY_COLOR = 0x55           # fg=5,bg=5 (light blue)
ROCK_COLOR = 0x8B          # fg=8 (medium red, unchanged), bg=11 (light yellow)
SAND_COLOR = 0xAB          # fg=10 (dark yellow), bg=11 (light yellow)
N_COLOR_GROUPS = 32
COLORDATA = [SKY_COLOR] + [ROCK_COLOR] * (N_COLOR_GROUPS - 1)
for _g in SAND_GROUPS:
    COLORDATA[_g] = SAND_COLOR

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
    out.append(f"TERRAIN_BLANK_CODE EQU {BLANK_CODE}")
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
