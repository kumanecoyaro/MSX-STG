"""Converts Ebullet_16x16.json (the ZacoII/Flyer enemy bullet - "EBullet",
fired at the tank in 1 of 16 directions - round36-14 follow-up#11: "ザコ敵
の弾発射実装...ZakoII2種は反転時に添付データEBullet発射...発射は16方向")
into a 16x16 hw sprite pattern: same "8x8 source art embedded at the
top-left of an otherwise-blank 16x16 canvas" shape as sbeam_gen.py's own
sbeam_sprite() - the source JSON is itself already a 16x16 canvas, but
every uploaded row/col beyond the top-left 8x8 is already all-zero (only
the top-left 4x4 has real pixels - "コリジョンは左上4x4ドット"), so taking
just its own top-left 8x8 sub-tile as the TL quadrant and leaving BL/TR/BR
blank reproduces the source exactly.
"""
import json
import math
import os
from collections import defaultdict, Counter

HERE = os.path.dirname(os.path.abspath(__file__))
SPRITE_DIR = os.path.join(HERE, "sprites")


def load_bits(name):
    return json.load(open(os.path.join(SPRITE_DIR, f"{name}.json")))["bits"]


def to_bytes(tile8x8):
    out = []
    for row in tile8x8:
        b = 0
        for i, v in enumerate(row):
            if v:
                b |= (0x80 >> i)
        out.append(b)
    return out


def ebullet_sprite():
    bits = load_bits("Ebullet_16x16")
    tile = [row[0:8] for row in bits[0:8]]
    zero8 = [0, 0, 0, 0, 0, 0, 0, 0]
    return to_bytes(tile) + zero8 + zero8 + zero8


EBULLET_SPRITE = ebullet_sprite()


# ---- 16-direction aim table ----
# "発射タイミングの瞬間の自機を狙って直進...発射は16方向": at fire time,
# dx=(tank_x-firer_x), dy=(tank_y-firer_y) is reduced to the nearest of 16
# 22.5-degree-spaced directions using a cheap Z80-friendly fold (no
# multiply/divide, no trig): fold to the first 45-degree octant via
# sign-strip + conditional swap(|dx|,|dy|), pick the octant's own "near
# 0 degrees" vs "near 22.5 degrees" half via the integer test 5*minor>
# major (approximates the true tan(11.25)=0.199 MIDPOINT cutoff between
# the 2 candidate directions with a cheap shift-add-compare, no real
# multiply/divide needed since 5x = x<<2 + x), then unfold via a small
# 16-entry lookup table (DIR16_LUT, indexed by the 4-bit fold code
# fx<<3|fy<<2|sw<<1|half) - built here by DENSE SAMPLING (every (dx,dy)
# in a +-200x+-150 grid) rather than hand-derived reflection algebra,
# because the 4 combined sign/swap reflections make manual derivation
# extremely easy to get subtly wrong (this generator itself did, on the
# first attempt - see this round's own HANDOFF entry).
#
# An earlier version of this threshold used a much cheaper "2*minor>
# major" test (~26.57 degree cutoff, not the true 11.25 degree midpoint)
# - it happened to leave max circular error at 1 of 16 steps in a bulk
# stress test same as this version does, so the stress-test number alone
# didn't catch it, but it silently pointed EVERY exactly-horizontal or
# exactly-vertical shot (dx>0,dy=0 etc - fold code0's own majority, the
# single most common/visible real case) 22.5 degrees off dead level -
# caught by this round's own EBULLET_DIR16 test suite (call_routine()
# against this exact reference, not just eyeballing the LUT), not by the
# stress test's own aggregate error distribution. 5*minor>major fixes
# every exact cardinal (dx=0 or dy=0) case; the analogous exact-diagonal
# tie (|dx|==|dy|) still rounds 1 step short (e.g. (1,1) lands on dir1/
# 22.5 degrees instead of the "true" dir2/45 degrees) because a single
# half-bit fundamentally can't distinguish 3 candidates (0/22.5/45) - the
# exact tie is inherently ambiguous under this 2-way fold scheme,
# whichever threshold is chosen. Accepted: an off-by-1-step diagonal is
# far less visually obvious than an off-by-1-step cardinal, and this is
# an "aim and forget" bullet, not a precision instrument.
def _fold_code(dx, dy):
    fx = 1 if dx < 0 else 0
    fy = 1 if dy < 0 else 0
    ax, ay = abs(dx), abs(dy)
    sw = 1 if ax < ay else 0
    if sw:
        ax, ay = ay, ax
    half = 1 if (5 * ay > ax) else 0
    return (fx << 3) | (fy << 2) | (sw << 1) | half


def _exact_dir16(dx, dy):
    if dx == 0 and dy == 0:
        return 0
    ang = math.degrees(math.atan2(dy, dx)) % 360
    return round(ang / 22.5) % 16


def build_dir16_lut():
    samples = defaultdict(list)
    for dx in range(-200, 201):
        for dy in range(-150, 151):
            if dx == 0 and dy == 0:
                continue
            samples[_fold_code(dx, dy)].append(_exact_dir16(dx, dy))
    return [Counter(samples[c]).most_common(1)[0][0] for c in range(16)]


DIR16_LUT = build_dir16_lut()

# 実機フィードバック対応 ("ZakoII2種の弾も速度を下げて"): was 3.
EBULLET_SPEED = 2   # px/frame magnitude - similar order to other established bullet speeds (FLYER_SPEED=2, boss beams 2-5)


def build_step_tables(speed):
    dx_table, dy_table = [], []
    for d in range(16):
        ang = math.radians(d * 22.5)
        dx_table.append(round(speed * math.cos(ang)))
        dy_table.append(round(speed * math.sin(ang)))
    return dx_table, dy_table


EBULLET_DX_TABLE, EBULLET_DY_TABLE = build_step_tables(EBULLET_SPEED)


def db_bytes(byte_list):
    return "    DB " + ",".join(f"{b}" for b in byte_list)


def db_signed_bytes(byte_list):
    return "    DB " + ",".join(f"{b & 0xFF}" for b in byte_list)


def emit_asm_tables():
    out = ["; ===== EBullet hw sprite art + 16-direction aim tables: generated by ebullet_gen.py, do not hand-edit ====="]
    out.append("EBULLET_SPRITE:")
    out.append(db_bytes(EBULLET_SPRITE))
    out.append("EBULLET_DIR16_LUT:")
    out.append(db_bytes(DIR16_LUT))
    out.append("EBULLET_DX_TABLE:")
    out.append(db_signed_bytes(EBULLET_DX_TABLE))
    out.append("EBULLET_DY_TABLE:")
    out.append(db_signed_bytes(EBULLET_DY_TABLE))
    return "\n".join(out)


if __name__ == "__main__":
    print(f"EBullet converted: {len(EBULLET_SPRITE)} bytes (16x16 hw sprite pattern)")
    print("DIR16_LUT:", DIR16_LUT)
    print("DX_TABLE:", EBULLET_DX_TABLE)
    print("DY_TABLE:", EBULLET_DY_TABLE)
