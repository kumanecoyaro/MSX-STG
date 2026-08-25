"""Verifies the boss death/explosion sequence (INIT_BOSS_EXPLOSION/
UPDATE_BOSS_EXPLOSION/BOSS_EXPL_DRAW_CIRCLE et al.) against a geometry
computed independently in Python, not by re-deriving expectations from
the same half-width table the ASM itself uses - that would just prove
the two copies of the same logic agree, not that either is correct.

User's own spec (verbatim, paraphrased): defeated-while-BG-pose reverts
to sprite first; from the boss's own center, a filled white BG circle
grows cell-by-cell (1 cell = 1px for the algorithm) up to a 48px (=6
cell) radius, clipped to the screen; the boss sprite blinks throughout
since BG would otherwise be hidden behind it; once at max radius, a
full-screen-width BG line is drawn and the boss sprite is hidden for
good; the circle then shrinks back down, and once it's back to a single
cell the line is erased; that last cell blinks for 120 frames, then
vanishes.
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, call_routine

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)

BOSS_ACT = sym["BOSS_ACT"]
BOSS_X = sym["BOSS_X"]
BOSS_Y = sym["BOSS_Y"]
BOSS_PHASE = sym["BOSS_PHASE"]
BOSS_SPAWNX = sym["BOSS_SPAWNX"]
BOSS_SPAWN_Y = sym["BOSS_SPAWN_Y"]
NIGHT_ROW = sym["NIGHT_ROW"]
NIGHT_END_ROW = sym["NIGHT_END_ROW"]
BOSS_SPR_BASE_SLOT = sym["BOSS_SPR_BASE_SLOT"]
BOSS_SPRITE_ATTRS = sym["BOSS_SPRITE_ATTRS"]
HUD_ROW_BLANK_CODE = sym["HUD_ROW_BLANK_CODE"]
SASAPI_HAND_CODE_BASE = sym["SASAPI_HAND_CODE_BASE"]
BULLET_ROCK_ROW_MIN = sym["BULLET_ROCK_ROW_MIN"]
SKYSAND_CODE = sym["SKYSAND_CODE"]
NIGHT_CODE = sym["NIGHT_CODE"]
TERRAIN_BLANK_CODE = sym["TERRAIN_BLANK_CODE"]
SKY_BLANK_CODE = sym["SKY_BLANK_CODE"]

BOSS_EXPL_STATE = sym["BOSS_EXPL_STATE"]
BOSS_EXPL_RADIUS = sym["BOSS_EXPL_RADIUS"]
BOSS_EXPL_TIMER = sym["BOSS_EXPL_TIMER"]
BOSS_EXPL_CX = sym["BOSS_EXPL_CX"]
BOSS_EXPL_CY = sym["BOSS_EXPL_CY"]
BOSS_EXPL_BLINK = sym["BOSS_EXPL_BLINK"]
STATE_SPARK = sym["BOSS_EXPL_STATE_SPARK"]
STATE_GROW = sym["BOSS_EXPL_STATE_GROW"]
STATE_SHRINK = sym["BOSS_EXPL_STATE_SHRINK"]
STATE_FLASH = sym["BOSS_EXPL_STATE_FLASH"]
STATE_DONE = sym["BOSS_EXPL_STATE_DONE"]
MAXR = sym["BOSS_EXPL_MAXR"]
STEP_FRAMES = sym["BOSS_EXPL_STEP_FRAMES"]
BLINK_PERIOD = sym["BOSS_EXPL_BLINK_PERIOD"]
FINAL_FLASH_FRAMES = sym["BOSS_EXPL_FINAL_FLASH_FRAMES"]
WHITE_CODE = sym["BOSS_EXPL_WHITE_CODE"]
ORIGIN_RANGE = sym["BOSS_EXPL_ORIGIN_RANGE"]
FLIGHT_MIN_DIST = sym["BOSS_EXPL_FLIGHT_MIN_DIST"]
FLIGHT_MAX_DIST = sym["BOSS_EXPL_FLIGHT_MAX_DIST"]
SPARK_DURATION = sym["BOSS_EXPL_SPARK_DURATION"]
SPARK_PER_FRAME = sym["BOSS_EXPL_SPARK_PER_FRAME"]
SPARK_CODE_TL = sym["BOSS_EXPL_SPARK_CODE_TL"]
SPARK_CODE_BL = sym["BOSS_EXPL_SPARK_CODE_BL"]
SPARK_CODE_TR = sym["BOSS_EXPL_SPARK_CODE_TR"]
SPARK_CODE_BR = sym["BOSS_EXPL_SPARK_CODE_BR"]
SPARK_CODES = {SPARK_CODE_TL, SPARK_CODE_BL, SPARK_CODE_TR, SPARK_CODE_BR}
BOSS_SPRITE_HIDDEN_Y = 209
# 8 compass directions (dx,dy each in {-1,0,1}) x distance FLIGHT_MIN_
# DIST..FLIGHT_MAX_DIST - independent Python re-derivation of BOSS_EXPL_
# FLIGHT_TABLE's own 24 entries, NOT read from the ASM's own table, so
# this genuinely cross-checks it rather than just restating it.
FLIGHT_DIRS = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]
FLIGHT_VECTORS = {
    (ddx * dist, ddy * dist)
    for ddx, ddy in FLIGHT_DIRS
    for dist in range(FLIGHT_MIN_DIST, FLIGHT_MAX_DIST + 1)
}
# a spark's final position is origin(+/-ORIGIN_RANGE) + flight(a vector
# from FLIGHT_VECTORS, magnitude up to FLIGHT_MAX_DIST on any one axis) -
# two stacked random draws, not one flat box - plus 1 more cell for a
# 16x16 spark's own spread beyond its anchor.
SPARK_BOX_MARGIN = ORIGIN_RANGE + FLIGHT_MAX_DIST + 1


def run_spark_phase(cpu, cx, cy):
    """Fast-forwards through the whole SPARK phase ("ボスの中心の32x32の
    範囲でランダムに...ウェイトなしで派手に沢山 3秒くらい") one frame at a
    time. Returns a dict:
    - spark_seen: every cell (within the legal scatter box) that ever
      showed ANY of the 4 spark quadrant codes across the whole burst
    - per_frame_live_counts: how many spark cells are showing at the END
      of each individual frame (bounded by the erase-then-redraw design -
      see the "never accumulates" check below)
    - boss_hidden_seen: True if the boss sprite was ever hidden (Y=209)
      during the burst - it must NOT be, per round32's own follow-up fix
      ("なぜ爆発エフェクト中にボス消してる 消さないでくれ BGでやってる
      意味がない")
    - saw_8x8/saw_16x16: whether a lone TL-only spark and a full 2x2
      TL/BL/TR/BR quad were each independently observed at least once -
      "爆発キャラは8x8のほうではなく16x16のほうで ランダムで混ぜてもいい
      がな" (CX/CY are picked comfortably clear of every screen edge by
      every caller, so a real quad is never partially clipped here -
      this heuristic is reliable for the interior case this test uses).
    """
    spark_seen = set()
    per_frame_live_counts = []
    boss_hidden_seen = False
    saw_8x8 = saw_16x16 = False
    for _ in range(SPARK_DURATION):
        call_routine(cpu, "UPDATE_BOSS_EXPLOSION")
        if boss_sat_y(cpu) == BOSS_SPRITE_HIDDEN_Y:
            boss_hidden_seen = True
        count = 0
        for dy in range(-SPARK_BOX_MARGIN, SPARK_BOX_MARGIN + 1):
            row = cy + dy
            if not (0 <= row <= 23):
                continue
            for dx in range(-SPARK_BOX_MARGIN, SPARK_BOX_MARGIN + 1):
                col = cx + dx
                if not (0 <= col <= 31):
                    continue
                if cpu.vram[cell_addr(col, row)] in SPARK_CODES:
                    count += 1
                    spark_seen.add((col, row))
                if cpu.vram[cell_addr(col, row)] == SPARK_CODE_TL:
                    is_quad = (
                        0 <= col + 1 <= 31 and 0 <= row + 1 <= 23
                        and cpu.vram[cell_addr(col, row + 1)] == SPARK_CODE_BL
                        and cpu.vram[cell_addr(col + 1, row)] == SPARK_CODE_TR
                        and cpu.vram[cell_addr(col + 1, row + 1)] == SPARK_CODE_BR
                    )
                    if is_quad:
                        saw_16x16 = True
                    else:
                        saw_8x8 = True
        per_frame_live_counts.append(count)
    return {
        "spark_seen": spark_seen,
        "per_frame_live_counts": per_frame_live_counts,
        "boss_hidden_seen": boss_hidden_seen,
        "saw_8x8": saw_8x8,
        "saw_16x16": saw_16x16,
    }

SAT_BASE = 0x1B00
NAME_BASE = 0x1800


def cell_addr(col, row):
    return NAME_BASE + row * 32 + col


def expected_bg_code(row, night_row):
    """Independent Python re-derivation of BOSS_EXPL_BG_CODE_FOR_ROW's
    own row->true-background-code rules (which themselves mirror
    ERASE_BULLET_CELL's day/night-aware restore logic) - NOT calling
    into the ASM, so this genuinely cross-checks it rather than just
    restating it. This directly targets the real-hardware/screenshot
    bug ("Sandskyとその下のラインは...復元しないとスクショのように欠け
    てしまう"): SkySand(16)/Sand(17-19) are one-time-drawn, non-blank
    tiles, not just "more sky"."""
    if row < BULLET_ROCK_ROW_MIN:
        return HUD_ROW_BLANK_CODE if night_row >= row else SKY_BLANK_CODE
    if row < BULLET_ROCK_ROW_MIN + 4:
        if row == BULLET_ROCK_ROW_MIN:
            return NIGHT_CODE if night_row >= NIGHT_END_ROW else SKYSAND_CODE
        return TERRAIN_BLANK_CODE
    return TERRAIN_BLANK_CODE  # defensive fallback, not realistically reached


def expected_circle(cx, cy, radius):
    """Independent Python re-derivation of the filled-disk membership
    test (dx^2+dy^2<=radius^2), clipped to the real screen - NOT reading
    the ASM's own ring tables, so this genuinely cross-checks the ASM's
    geometry rather than just restating it."""
    white = set()
    for dy in range(-MAXR, MAXR + 1):
        row = cy + dy
        if not (0 <= row <= 23):
            continue
        for dx in range(-MAXR, MAXR + 1):
            col = cx + dx
            if not (0 <= col <= 31):
                continue
            if dx * dx + dy * dy <= radius * radius:
                white.add((col, row))
    return white


def assert_box_matches(cpu, cx, cy, radius, label, line_active=False, night_row=NIGHT_END_ROW):
    """Checks not just white-vs-not, but the EXACT expected code for
    every non-white cell too (the real background per expected_bg_code)
    - a cell that's neither the correct white nor the correct
    background is exactly the "hole" shape the real-hardware screenshot
    showed. line_active=True (SHRINK, once the full-width line exists)
    means the center row (dy=0) is the line's own row, not the circle's
    - BOSS_EXPL_APPLY_RING deliberately skips it during SHRINK (the fix
    for "ラインが円の範囲で消えてる" - restoring it mid-shrink would eat
    into the still-solid line well before the real erase-line step), so
    every on-screen cell in that row is expected white regardless of the
    circle's own current radius."""
    expected_white = expected_circle(cx, cy, radius)
    if line_active:
        for dx in range(-MAXR, MAXR + 1):
            col = cx + dx
            if 0 <= col <= 31:
                expected_white.add((col, cy))
    mismatches = []
    for dy in range(-MAXR, MAXR + 1):
        row = cy + dy
        if not (0 <= row <= 23):
            continue
        for dx in range(-MAXR, MAXR + 1):
            col = cx + dx
            if not (0 <= col <= 31):
                continue
            code = cpu.vram[cell_addr(col, row)]
            if (col, row) in expected_white:
                expected = WHITE_CODE
            else:
                expected = expected_bg_code(row, night_row)
            if code != expected:
                mismatches.append((col, row, code, expected))
    check(f"{label}: radius={radius} box matches independently-computed circle+background "
          f"({len(mismatches)} mismatches)", not mismatches)


def boss_sat_y(cpu):
    return cpu.vram[SAT_BASE + BOSS_SPR_BASE_SLOT * 4]


def setup_boss(cpu, x, y=BOSS_SPAWN_Y, phase=0):
    cpu.mem[BOSS_ACT] = 1
    cpu.mem[BOSS_X] = x
    cpu.mem[BOSS_Y] = y
    cpu.mem[BOSS_PHASE] = phase
    # the boss only ever exists after BOSS_SPAWN_TICK(999), long past
    # NIGHT_START_TICK(850) - by then the whole sky band is always
    # already fully night-swept (same assumption DRAW_SASAPI_HAND/
    # ERASE_SASAPI_HAND already rely on), so match that here instead of
    # leaving NIGHT_ROW at its fresh-boot default (0, "still daytime") -
    # a boss death can never actually happen during the day.
    #
    # Poking NIGHT_ROW alone isn't enough: it's just CHECK_NIGHT's own
    # progress counter, not the VRAM content - real gameplay keeps both
    # in sync by actually running the sweep every frame, but a direct
    # poke here would leave the real name-table cells still showing
    # their fresh-boot daytime tiles (SKY_BLANK_CODE/SKYSAND_CODE)
    # while NIGHT_ROW claims "already dark", an inconsistency that
    # doesn't exist in real play and would make assert_box_matches'
    # own real background checks fail for the wrong reason. So paint
    # the actual VRAM to match too - rows0-15 solidified black (what
    # CHECK_NIGHT's own sweep leaves behind every row it's passed),
    # row16 the permanent striped NIGHT_CODE leading row (what it never
    # advances past, per NIGHT_END_ROW - see BOSS_EXPL_BG_CODE_FOR_ROW's
    # own comment on why row16 needs its own case at all).
    cpu.mem[NIGHT_ROW] = NIGHT_END_ROW
    for row in range(0, NIGHT_END_ROW):
        for col in range(32):
            cpu.vram[cell_addr(col, row)] = HUD_ROW_BLANK_CODE
    for col in range(32):
        cpu.vram[cell_addr(col, NIGHT_END_ROW)] = NIGHT_CODE
    # a plausible last-drawn sprite Y (so the grow-phase blink has a real,
    # non-209 value to restore) - DRAW_BOSS would normally have set this.
    # FLUSH_BOSS_SPRITES reads FROM this RAM buffer and writes it out to
    # VRAM/OAM - poking cpu.vram directly (the OAM side) would just get
    # silently overwritten by the very first FLUSH_BOSS_SPRITES call.
    for q in range(16):
        cpu.mem[BOSS_SPRITE_ATTRS + q * 4] = y
    # round32: actually FLUSH this to VRAM/OAM too, not just the RAM
    # staging buffer - real gameplay keeps the SAT in sync every frame
    # via the normal alive-boss update loop (DRAW_BOSS+FLUSH_BOSS_SPRITES)
    # before a death can ever happen; skipping this here would leave the
    # real OAM at its untouched fresh-boot state, making a "was the boss
    # sprite ever hidden" check after death pass/fail for the wrong
    # reason (same class of test-only inconsistency as the NIGHT_ROW fix
    # above - not a real ASM bug either time).
    call_routine(cpu, "FLUSH_BOSS_SPRITES")


# ---------------------------------------------------------------------
# 1: "まずボスがBG描画される右端で倒された場合はスプライトに戻す" -
# defeated while parked in the attack pose (BOSS_PHASE=1) reverts to
# sprite mode: hand art erased, BOSS_PHASE back to 0.
# ---------------------------------------------------------------------
cpu = fresh_cpu()
setup_boss(cpu, x=BOSS_SPAWNX, y=BOSS_SPAWN_Y, phase=1)
call_routine(cpu, "DRAW_SASAPI_HAND")  # put real hand art on screen first
check("hand art really is on screen before death (sanity check)",
      cpu.vram[0x18F8] == SASAPI_HAND_CODE_BASE)
call_routine(cpu, "CHPBOSS_DESTROY")
check("BOSS_PHASE reverted to 0 (sprite mode) after dying mid-pose",
      cpu.mem[BOSS_PHASE] == 0)
check("hand art erased (name-table cell back to HUD_ROW_BLANK_CODE)",
      cpu.vram[0x18F8] == HUD_ROW_BLANK_CODE)
check("explosion sequence started (state=SPARK) even from the BG-pose death",
      cpu.mem[BOSS_EXPL_STATE] == STATE_SPARK)
check("boss sprite explicitly re-shown (not left hidden from the pose) so SPARK's "
      "own BG sparks have a visible sprite to sit 'behind' - "
      "\"消さないでくれ BGでやってる意味がない\"",
      boss_sat_y(cpu) != BOSS_SPRITE_HIDDEN_Y)

# ---------------------------------------------------------------------
# 2: center-cell capture - "倒した位置のボス中心から"
# ---------------------------------------------------------------------
cpu = fresh_cpu()
setup_boss(cpu, x=96, y=BOSS_SPAWN_Y, phase=0)
call_routine(cpu, "CHPBOSS_DESTROY")
expected_cx = (96 + 32) // 8
expected_cy = (BOSS_SPAWN_Y + 32) // 8
check(f"BOSS_EXPL_CX captured correctly ({expected_cx})", cpu.mem[BOSS_EXPL_CX] == expected_cx)
check(f"BOSS_EXPL_CY captured correctly ({expected_cy})", cpu.mem[BOSS_EXPL_CY] == expected_cy)
check("BOSS_ACT=2 (destroyed)", cpu.mem[BOSS_ACT] == 2)
check("state is SPARK immediately after destruction (burst plays before the circle)",
      cpu.mem[BOSS_EXPL_STATE] == STATE_SPARK)
check("BOSS_EXPL_RADIUS holds SPARK's own slot0-empty sentinel (0FFh) right after "
      "destruction, not a real radius yet - it's reused as SPARK's own slot0 row "
      "storage until GROW begins (see BOSS_EXPL_SPARK_SLOT0_ROW's own comment)",
      cpu.mem[BOSS_EXPL_RADIUS] == 0xFF)
check("circle not drawn yet - SPARK runs first",
      cpu.vram[cell_addr(expected_cx, expected_cy)] != WHITE_CODE)
check("boss sprite still visible right at the start of SPARK (patrol-death case "
      "never hides it in the first place) - \"消さないでくれ BGでやってる意味がない\"",
      boss_sat_y(cpu) != BOSS_SPRITE_HIDDEN_Y)

CX, CY = expected_cx, expected_cy  # comfortably clear of every screen edge at max radius

# ---------------------------------------------------------------------
# 2a: BOSS_EXPL_PICK_FLIGHT itself, exercised directly (not just inferred
# from combined origin+flight landing positions, which can't isolate the
# flight component alone) - "悪くはないが飛びすぎたな 1から3セルランダ
# ムで". Every returned (dx,dy) must be one of the 24 independently-
# computed FLIGHT_VECTORS, distance always 1-3 (never 0, never >3 on any
# axis), and a large enough sample should hit every one of the 24.
# ---------------------------------------------------------------------
def signed8(v):
    return v - 256 if v >= 128 else v


seen_vectors = set()
for _ in range(2000):
    call_routine(cpu, "BOSS_EXPL_PICK_FLIGHT")
    dx, dy = signed8(cpu.c), signed8(cpu.b)
    seen_vectors.add((dx, dy))

check("every BOSS_EXPL_PICK_FLIGHT draw is one of the 24 valid (direction,distance) "
      f"vectors ({len(seen_vectors)} distinct ones seen over 2000 draws)",
      seen_vectors <= FLIGHT_VECTORS)
check(f"flight distance is always in {FLIGHT_MIN_DIST}..{FLIGHT_MAX_DIST} cells on "
      "every axis - never 0 (no-op flight) and never further than the max",
      all(FLIGHT_MIN_DIST <= max(abs(dx), abs(dy)) <= FLIGHT_MAX_DIST for dx, dy in seen_vectors))
check("all 24 valid vectors were actually reachable (full LUT coverage over 2000 draws)",
      seen_vectors == FLIGHT_VECTORS)

# ---------------------------------------------------------------------
# 2b: SPARK burst itself - "爆発範囲を元の64x64に てかこれはエフェクトが
# 飛ぶ範囲ではなく原点だからな そこからランダム方向に1から3セル飛ぶんだ
# ぞ" - origin (the boss's own 64x64 body) + an independent random flight
# (1-3 cells, a random compass direction), not one flat box. Plus the
# earlier erase/redraw fix - "ボックス範囲で消去もしてないから飛んでる
# かどうかもわからない ただ64x64がBGで埋まってるだけだ" - and "爆発キャ
# ラは8x8のほうではなく16x16のほうで ランダムで混ぜてもいいがな ウェイ
# トなしで派手に沢山 3秒くらい".
# ---------------------------------------------------------------------
result = run_spark_phase(cpu, CX, CY)
spark_seen = result["spark_seen"]
per_frame_live_counts = result["per_frame_live_counts"]

legal_spark_cells = set()
origin_cells = set()
for dy in range(-SPARK_BOX_MARGIN, SPARK_BOX_MARGIN + 1):
    row = CY + dy
    if not (0 <= row <= 23):
        continue
    for dx in range(-SPARK_BOX_MARGIN, SPARK_BOX_MARGIN + 1):
        col = CX + dx
        if not (0 <= col <= 31):
            continue
        legal_spark_cells.add((col, row))
        if -ORIGIN_RANGE <= dx <= ORIGIN_RANGE and -ORIGIN_RANGE <= dy <= ORIGIN_RANGE:
            origin_cells.add((col, row))

check(f"every spark landed inside the CX/CY +/-{SPARK_BOX_MARGIN} scatter box "
      f"(origin's own +/-{ORIGIN_RANGE} plus flight's own +/-{FLIGHT_MAX_DIST}, plus a "
      "16x16 spark's own +1-cell reach), none outside it",
      spark_seen <= legal_spark_cells)
check("sparks genuinely scattered across a meaningfully large portion of the box, "
      f"not stuck on one or two cells ({len(spark_seen)}/{len(legal_spark_cells)} "
      "cells ever hit)", len(spark_seen) >= 20)
check("the boss's own 64x64 body (the origin area) sees plenty of hits too, not "
      "just far-flung flight endpoints - confirms sparks genuinely originate from "
      "within the body, not just from its edge",
      len(spark_seen & origin_cells) >= 10)
check("boss sprite was NEVER hidden during the whole SPARK burst - "
      "\"なぜ爆発エフェクト中にボス消してる 消さないでくれ BGでやってる意味がない\"",
      not result["boss_hidden_seen"])
check("both spark sizes were actually used - a lone 8x8 tile and a full 16x16 "
      "(4-quadrant) tile were each independently observed at least once",
      result["saw_8x8"] and result["saw_16x16"])
# the direct regression guard for "ただ64x64がBGで埋まってるだけだ": if the
# erase-before-spawn step were ever dropped again, live sparks would only
# ever accumulate (monotonically non-decreasing, eventually filling the
# whole box) instead of staying bounded by what THIS frame alone can add -
# at most SPARK_PER_FRAME sparks, each at most 4 cells (16x16).
max_possible_per_frame = SPARK_PER_FRAME * 4
check(f"live spark count never exceeds what a single frame's own batch could "
      f"draw ({max_possible_per_frame}) - confirms sparks are erased before each "
      "frame's redraw, not just piling up into a solid block",
      all(c <= max_possible_per_frame for c in per_frame_live_counts))
check("the live spark count genuinely fluctuates frame to frame (real flicker, "
      "not a static picture)", len(set(per_frame_live_counts)) >= 3)
check(f"SPARK phase lasts exactly {SPARK_DURATION} frames then hands off to GROW",
      cpu.mem[BOSS_EXPL_STATE] == STATE_GROW)
# scoped to spark_seen (cells that were EVER actually drawn as a spark at
# some point) rather than the whole legal box: the new precise-tracking
# design (BOSS_EXPL_SPARK_SLOT) only ever touches cells a spark actually
# lands on, unlike the old blanket-sweep design - a cell nothing ever
# happened to land on this particular random run is correctly left
# exactly as it was before SPARK started, not necessarily "the real
# background" the way a cell that WAS drawn-then-erased must be.
check("every cell that was ever a spark is correctly restored to real "
      "background by the time GROW begins - no leftover spark tiles",
      all(cpu.vram[cell_addr(c, r)] == expected_bg_code(r, NIGHT_END_ROW)
          for (c, r) in spark_seen if (c, r) != (CX, CY)))

# ---------------------------------------------------------------------
# 2c: SPARK has completed - the original GROW-entry geometry picks up
# exactly as before ("倒した位置のボス中心から...円を...")
# ---------------------------------------------------------------------
check("radius still at 0 right as GROW begins (just the center cell)",
      cpu.mem[BOSS_EXPL_RADIUS] == 0)
check("initial 1-cell circle already drawn now that GROW has begun",
      cpu.vram[cell_addr(CX, CY)] == WHITE_CODE)


# ---------------------------------------------------------------------
# 3: GROW phase - circle geometry at every radius step, and the boss
# sprite blinking throughout ("この時当然BGはボスの後ろに隠れてしまうん
# でボスは点滅表示").
# ---------------------------------------------------------------------
assert_box_matches(cpu, CX, CY, 0, "GROW")

seen_shown = seen_hidden = False
for frame in range(1, STEP_FRAMES * MAXR + 1):
    call_routine(cpu, "UPDATE_BOSS_EXPLOSION")
    y = boss_sat_y(cpu)
    if y == 209:
        seen_hidden = True
    elif y == BOSS_SPAWN_Y:
        seen_shown = True
    if frame % STEP_FRAMES == 0:
        expected_radius = min(frame // STEP_FRAMES, MAXR)
        check(f"GROW frame {frame}: radius advanced to {expected_radius}",
              cpu.mem[BOSS_EXPL_RADIUS] == expected_radius)
        assert_box_matches(cpu, CX, CY, expected_radius, "GROW")

check("boss sprite was shown at least once during GROW (blink 'on')", seen_shown)
check("boss sprite was hidden at least once during GROW (blink 'off')", seen_hidden)
check("GROW reached max radius", cpu.mem[BOSS_EXPL_RADIUS] == MAXR)
check("state is still GROW right at max radius (transition happens on the NEXT step)",
      cpu.mem[BOSS_EXPL_STATE] == STATE_GROW)

# ---------------------------------------------------------------------
# 4: grow->shrink transition - "その後円中心から左右に画面幅のBGライン
# を引いてボス表示は終了"
# ---------------------------------------------------------------------
for _ in range(STEP_FRAMES):
    call_routine(cpu, "UPDATE_BOSS_EXPLOSION")
check("state advanced to SHRINK once growth timed out at max radius",
      cpu.mem[BOSS_EXPL_STATE] == STATE_SHRINK)
row_codes = [cpu.vram[cell_addr(c, CY)] for c in range(32)]
check("full-screen-width line drawn at the center row (all 32 cols white)",
      all(c == WHITE_CODE for c in row_codes))
check("boss sprite hidden for good once the line is drawn", boss_sat_y(cpu) == 209)

# confirm the boss sprite STAYS hidden through more frames (no more blink)
for _ in range(BLINK_PERIOD * 2):
    call_routine(cpu, "UPDATE_BOSS_EXPLOSION")
check("boss sprite never re-shown once in SHRINK (blinking was GROW-only)",
      boss_sat_y(cpu) == 209)

# ---------------------------------------------------------------------
# 5: SHRINK phase geometry, then the line erasing once back to 1 cell -
# "円を小さくして行き1セルになったら画面幅のラインを消す"
# ---------------------------------------------------------------------
# radius is still MAXR (the SHRINK-entry redraw hasn't fired a step yet
# after the settle-frames above re-armed the timer) - step through the
# full shrink from here. Checks the FULL-WIDTH line every single frame
# (not just at step boundaries) - this is the direct regression guard
# for "円の描画とラインの描画順の問題でラインが円の範囲で消えてる": the
# bug only showed up mid-step, between the box's own radius-step
# redraws, so a step-boundary-only check would have missed it same as
# the original version of this test did.
frames_used = 0
line_ate_into = []
while cpu.mem[BOSS_EXPL_STATE] == STATE_SHRINK and frames_used < STEP_FRAMES * (MAXR + 2):
    call_routine(cpu, "UPDATE_BOSS_EXPLOSION")
    frames_used += 1
    # the one legitimate exception: the exact frame SHRINK hands off to
    # FLASH is when the line is SUPPOSED to go from solid to erased -
    # only frames that are STILL mid-shrink afterward need the line
    # untouched.
    if cpu.mem[BOSS_EXPL_STATE] == STATE_SHRINK:
        row_codes = [cpu.vram[cell_addr(c, CY)] for c in range(32)]
        if not all(c == WHITE_CODE for c in row_codes):
            line_ate_into.append((frames_used, row_codes))
    if frames_used % STEP_FRAMES == 0 and cpu.mem[BOSS_EXPL_STATE] == STATE_SHRINK:
        assert_box_matches(cpu, CX, CY, cpu.mem[BOSS_EXPL_RADIUS], "SHRINK", line_active=True)

check(f"the full-width line stays completely solid white on EVERY frame throughout "
      f"SHRINK, never partially erased by the shrinking circle ({len(line_ate_into)} "
      f"bad frames)", not line_ate_into)

check("SHRINK finished and advanced to FLASH", cpu.mem[BOSS_EXPL_STATE] == STATE_FLASH)
row_codes = [cpu.vram[cell_addr(c, CY)] for c in range(32) if c != CX]
expected_line_bg = expected_bg_code(CY, NIGHT_END_ROW)
check("line erased once radius reached 0 (whole row restored to the correct "
      "background except the center cell)",
      all(c == expected_line_bg for c in row_codes))
check("center cell still white right as FLASH begins",
      cpu.vram[cell_addr(CX, CY)] == WHITE_CODE)
check("final-flash timer set to exactly 120 frames", cpu.mem[BOSS_EXPL_TIMER] == FINAL_FLASH_FRAMES)

# ---------------------------------------------------------------------
# 6: final 120-frame flash + vanish - "最後の1セルを120フレ点滅させ消滅"
# ---------------------------------------------------------------------
seen_on = seen_off = False
for frame in range(1, FINAL_FLASH_FRAMES + 1):
    call_routine(cpu, "UPDATE_BOSS_EXPLOSION")
    code = cpu.vram[cell_addr(CX, CY)]
    if code == WHITE_CODE:
        seen_on = True
    elif code == HUD_ROW_BLANK_CODE:
        seen_off = True
    if frame < FINAL_FLASH_FRAMES:
        check(f"FLASH frame {frame}: sequence not marked done early",
              cpu.mem[BOSS_EXPL_STATE] == STATE_FLASH) if frame == 1 else None

check("final cell blinked on at least once during the 120 frames", seen_on)
check("final cell blinked off at least once during the 120 frames", seen_off)
check("sequence marked DONE after exactly 120 flash frames", cpu.mem[BOSS_EXPL_STATE] == STATE_DONE)
check("final cell erased for good (vanished)", cpu.vram[cell_addr(CX, CY)] == HUD_ROW_BLANK_CODE)

# further frames are a genuine no-op once DONE
snapshot = bytes(cpu.vram[cell_addr(0, CY):cell_addr(0, CY) + 32])
for _ in range(30):
    call_routine(cpu, "UPDATE_BOSS_EXPLOSION")
check("DONE state is a permanent no-op (center row unchanged by further updates)",
      bytes(cpu.vram[cell_addr(0, CY):cell_addr(0, CY) + 32]) == snapshot)

# ---------------------------------------------------------------------
# 6b: direct regression check for the real-hardware/screenshot bug -
# "Sandskyとその下のラインは更新しない1度書きなので復元しないとスクショ
# のように欠けてしまう". CY=11 -> the box (rows5-17) genuinely reaches
# row16 (SkySand) and row17 (Sand/TERRAIN_BLANK_CODE), not just pure
# sky - confirm the WHOLE sequence leaves both showing their real,
# correct tile (not blank, not white) now that it's over, exactly the
# spot the screenshot showed as a black hole.
row16_codes = [cpu.vram[cell_addr(c, 16)] for c in range(CX - MAXR, CX + MAXR + 1) if 0 <= c <= 31]
row17_codes = [cpu.vram[cell_addr(c, 17)] for c in range(CX - MAXR, CX + MAXR + 1) if 0 <= c <= 31]
check("SkySand row (16) restored to NIGHT_CODE after the full sequence, not left blank/white",
      all(c == NIGHT_CODE for c in row16_codes))
check("Sand row (17) restored to TERRAIN_BLANK_CODE after the full sequence, not left blank/white",
      all(c == TERRAIN_BLANK_CODE for c in row17_codes))


# ---------------------------------------------------------------------
# 7: clipping - "当然クリッピングして画面内のみ描画" - left edge (X=0)
# and right edge (X=BOSS_SPAWNX) both stay within the screen with no
# wraparound corruption of the adjacent row.
# ---------------------------------------------------------------------
for edge_name, edge_x in (("left", 0), ("right", BOSS_SPAWNX)):
    cpu = fresh_cpu()
    setup_boss(cpu, x=edge_x, y=BOSS_SPAWN_Y, phase=0)
    call_routine(cpu, "CHPBOSS_DESTROY")
    cx, cy = cpu.mem[BOSS_EXPL_CX], cpu.mem[BOSS_EXPL_CY]
    run_spark_phase(cpu, cx, cy)  # SPARK always runs first now; get past it to GROW
    check(f"clip-{edge_name}: GROW reached after the SPARK burst",
          cpu.mem[BOSS_EXPL_STATE] == STATE_GROW)
    # drive all the way to max radius - the widest clipping test - without
    # asserting on every intermediate step (already covered above).
    for _ in range(STEP_FRAMES * MAXR):
        call_routine(cpu, "UPDATE_BOSS_EXPLOSION")
    assert_box_matches(cpu, cx, cy, cpu.mem[BOSS_EXPL_RADIUS], f"clip-{edge_name}")
    # the row immediately above the box's own top row must be untouched -
    # a real regression here would show up as stray white cells from a
    # negative-column write wrapping into the previous row.
    above_row = cy - MAXR - 1
    if 0 <= above_row <= 23:
        row_codes = [cpu.vram[cell_addr(c, above_row)] for c in range(32)]
        check(f"clip-{edge_name}: the row just above the box is untouched",
              all(c != WHITE_CODE for c in row_codes))


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    sys.exit(1)
