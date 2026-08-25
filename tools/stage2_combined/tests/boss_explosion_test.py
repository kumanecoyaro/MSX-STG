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
STATE_GROW = sym["BOSS_EXPL_STATE_GROW"]
STATE_SHRINK = sym["BOSS_EXPL_STATE_SHRINK"]
STATE_FLASH = sym["BOSS_EXPL_STATE_FLASH"]
STATE_DONE = sym["BOSS_EXPL_STATE_DONE"]
MAXR = sym["BOSS_EXPL_MAXR"]
STEP_FRAMES = sym["BOSS_EXPL_STEP_FRAMES"]
BLINK_PERIOD = sym["BOSS_EXPL_BLINK_PERIOD"]
FINAL_FLASH_FRAMES = sym["BOSS_EXPL_FINAL_FLASH_FRAMES"]
WHITE_CODE = sym["BOSS_EXPL_WHITE_CODE"]

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
check("explosion sequence started (state=GROW) even from the BG-pose death",
      cpu.mem[BOSS_EXPL_STATE] == STATE_GROW)

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
check("radius starts at 0 (just the center cell)", cpu.mem[BOSS_EXPL_RADIUS] == 0)
check("initial 1-cell circle already drawn", cpu.vram[cell_addr(expected_cx, expected_cy)] == WHITE_CODE)

CX, CY = expected_cx, expected_cy  # comfortably clear of every screen edge at max radius


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
