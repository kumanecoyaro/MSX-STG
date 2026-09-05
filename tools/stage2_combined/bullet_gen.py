"""Converts the tank bullet sprites (8x8, Sprite Editor JSON) into VRAM
data for combined_test.asm.

round36-11 ("キャラデータ差し替え...今までは前と斜め2パターンだったが
3つのデータにわけ1発目水平撃ちBulletFU、2発目FM、3発目FLと切り替えて
ローテーションさせる 斜めも同様にUU、UM、ULで切り替え"): both the
straight (F) and diagonal (U) shot each grew from 1 static pose to 3
(BulletFU/FM/FL, BulletUU/UM/UL - U/M/L here mean the glyph's own
vertical position within its 8x8 cell, NOT left/right facing - that's
still the separate _L-suffixed mirror this file always generated).
VARIANT_NAMES below fixes the rotation order (index0 = the 1st shot
fired, ...) - combined_test.asm's own TRY_SPAWN_BULLET advances a
counter through these same 3 indices independently for F-type and
U-type shots.

BulletF (straight-ahead) stays a BG (background character) pattern,
drawn as name-table characters rather than a hardware sprite - "水平は
今のままで" (leave the horizontal shot as it is). See combined_test.asm's
BULLETF_SKY_CODE0/1/2 etc: each of the 3 rotation variants still needs
its own code per background color group it can appear over (SCREEN1
color is fixed per 8-code group, not per screen position), so 3
variants x 2 backgrounds (sky/rock) x 2 facings x (+night) is real
budget pressure - see combined_test.asm's own BULLETF_SKY_CODE0 comment
for exactly how round36-11 fit this into the available codes.

BulletU (diagonal, up+forward) is a hardware sprite in normal play -
"弾は斜めのみスプライトに変更" - since it no longer needs the sky/rock
BG color-matching dance at all (a hw sprite composites over whatever's
already drawn). Each of the 3 rotation variants' 8x8 source art is
embedded into the top-left 8x8 of an otherwise-blank 16x16 canvas (the
VDP is already running in 16x16 sprite mode for the tank/enemies, so a
new sprite has to be 16x16-shaped too) and converted the same TL/BL/TR/
BR quadrant-byte-order way tank_gen.py/enemy_gen.py already do for
their own 16x16 sprites - see block16_bytes there. Kept in the top-left
corner (not centered) so the sprite's own (Y,X) attribute can stay
exactly row*8,col*8, the same anchor point the old BG cell used.
round36-11: unlike F, U's hw sprite pattern budget has ZERO free slots
anywhere in the whole 256-slot table for 3 dedicated resident bitmaps
(let alone x2 facings) - see combined_test.asm's own WRITE_BULLETU_
SPRITE_VARIANT comment. All 3 variants (x2 facings) are exported here
regardless; combined_test.asm dynamically rewrites the single shared
PAT_BULLETU/PAT_BULLETU_L VRAM slot with whichever variant's bytes at
the moment a new diagonal shot spawns, rather than giving each variant
its own permanent slot.

BulletU's OTHER own use - the BG-cell fallback used only while
BOSS_ACT!=0 ("ボス戦になったら斜めショットをBG描画に変更", since the hw
sprite slots the diagonal shot would otherwise use collide with the
boss's own sprites during the fight) - does NOT rotate (round36-9/10's
own BG pattern-code budget audit left only 24 free codes total, and
F's own full rotation across sky/rock/night already needs all but 6 of
them - see combined_test.asm's own BULLETU_SKY_CODE comment). It keeps
using a single representative pose - VARIANT_NAMES[BOSS_BG_VARIANT]
picks which one (the middle pose, closest in spirit to the old single
BulletU.json this replaces).

Both poses also get a mirrored (left-facing) version for when the tank
itself is facing/firing left (see combined_test.asm's TANK_FACING) -
same "generate the flip yourself" approach as tank_gen.py's own
POSE_FLIP_OFFSET poses, reusing terrain_gen.py's hflip idea. For
BulletU the source 8x8 bits are mirrored in place and re-embedded at
the same top-left corner (not the whole 16x16 canvas flipped, which
would shift the visible pixels to the top-right and require a
compensating +8 X offset for no visual benefit).
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SPRITE_DIR = os.path.join(HERE, "sprites")

# Rotation order - index0 is the 1st shot fired, index1 the 2nd, index2
# the 3rd, then back to index0 - "1発目水平撃ちBulletFU、2発目FM、3発目
# FL...斜めも同様にUU、UM、UL".
VARIANT_NAMES_F = ["BulletFU_8x8", "BulletFM_8x8", "BulletFL_8x8"]
VARIANT_NAMES_U = ["BulletUU_8x8", "BulletUM_8x8", "BulletUL_8x8"]
BOSS_BG_VARIANT = 1  # BulletUM - see this file's own module docstring


def load_bits(name):
    return json.load(open(os.path.join(SPRITE_DIR, f"{name}.json")))["bits"]


def hflip_bits(bits):
    return [list(reversed(row)) for row in bits]


def to_bytes(tile8x8):
    out = []
    for row in tile8x8:
        b = 0
        for i, v in enumerate(row):
            if v:
                b |= (0x80 >> i)
        out.append(b)
    return out


def bullet_pattern(name, flipped=False):
    bits = load_bits(name)
    if flipped:
        bits = hflip_bits(bits)
    tile = [row[0:8] for row in bits[0:8]]
    return to_bytes(tile)


F_PATTERNS = [bullet_pattern(n) for n in VARIANT_NAMES_F]
F_PATTERNS_L = [bullet_pattern(n, flipped=True) for n in VARIANT_NAMES_F]

# Raw 8x8 BG-pattern version of U's own art (distinct from bullet_u_sprite()
# below, which pads it into a 16x16 hw sprite canvas) - single
# non-rotating pose only, see this file's own module docstring.
U_BG_PATTERN = bullet_pattern(VARIANT_NAMES_U[BOSS_BG_VARIANT])
U_BG_PATTERN_L = bullet_pattern(VARIANT_NAMES_U[BOSS_BG_VARIANT], flipped=True)


def bullet_u_sprite(name, flipped=False):
    """One U rotation variant's 8x8 art, embedded at the top-left of an
    otherwise-blank 16x16 sprite canvas: TL8,BL8,TR8,BR8 quadrant byte
    order (32 bytes), same layout as one of tank_gen.py's own 16x16
    sprite quadrants."""
    bits = load_bits(name)
    if flipped:
        bits = hflip_bits(bits)
    tile = [row[0:8] for row in bits[0:8]]
    zero8 = [0, 0, 0, 0, 0, 0, 0, 0]
    return to_bytes(tile) + zero8 + zero8 + zero8


U_SPRITES = [bullet_u_sprite(n) for n in VARIANT_NAMES_U]
U_SPRITES_L = [bullet_u_sprite(n, flipped=True) for n in VARIANT_NAMES_U]


def db_bytes(byte_list):
    return "    DB " + ",".join(f"{b}" for b in byte_list)


def emit_asm_tables():
    out = ["; ===== Bullet patterns: generated by bullet_gen.py, do not hand-edit ====="]
    for i in range(3):
        out.append(f"BULLET_F_PATTERN{i}:")
        out.append(db_bytes(F_PATTERNS[i]))
        out.append(f"BULLET_F_L_PATTERN{i}:")
        out.append(db_bytes(F_PATTERNS_L[i]))
    out.append("BULLET_U_PATTERN:")
    out.append(db_bytes(U_BG_PATTERN))
    out.append("BULLET_U_L_PATTERN:")
    out.append(db_bytes(U_BG_PATTERN_L))
    for i in range(3):
        out.append(f"BULLET_U_SPRITE{i}:")
        out.append(db_bytes(U_SPRITES[i]))
        out.append(f"BULLET_U_SPRITE{i}_L:")
        out.append(db_bytes(U_SPRITES_L[i]))
    return "\n".join(out)


if __name__ == "__main__":
    print("BulletF x3 converted, 8 bytes each (BG pattern)")
    print("BulletU x3 converted, 32 bytes each (16x16 hw sprite pattern)")
    tables_path = os.path.join(HERE, "bullet_tables.inc.asm")
    with open(tables_path, "w") as f:
        f.write(emit_asm_tables())
    print("wrote", tables_path)
