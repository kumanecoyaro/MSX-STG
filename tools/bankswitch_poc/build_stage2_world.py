"""Builds a full "stage 2 world" - an exact port of the real game
(same terrain/engine/graphics), but with the enemy roster trimmed to
SIMPLE-type only, plus a permanent "STAGE2" HUD label - for testing
the ASCII16 bank-switch mechanism against a REAL, fully-playable
continuation instead of a static placeholder screen.

Explicitly a throwaway test per the user: "Stage 1と全く同じ物をStage 2に
移植してくれ、ただ敵はシンプルのみで、これは後で作り直すからテストだ"
(port an exact copy of stage 1 into stage 2, but enemies simple-only,
this is a test since it'll be rebuilt later).

Does NOT touch src/CYBER_GD_BOSS.asm - takes the raw, unmodified source
text and transforms an in-memory copy, so the normal single-bank
production build stays completely unaffected. Assembled independently
from bank0/bank1 (the ORG addresses are identical - both worlds start
at 4000h and use the same window-A/window-B split - only the FILE
OFFSET differs).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(HERE, ".."))
from mini_z80asm import Assembler


def extract_simple_only_schedule():
    """Reads the REAL committed schedule and filters it down to just
    the type=simple entries (tick, Y), preserving original order/tick
    values, plus the original boss tick at the very end."""
    src_path = os.path.join(REPO, "src", "CYBER_GD_BOSS.asm")
    text = open(src_path, encoding="utf-8").read()
    a = Assembler(text)
    out = a.assemble()
    sym = a.symtab

    m = re.search(r"^SSC_FIRE:\n(.*?)(?=\n\S)", text, re.S | re.M)
    body = m.group(1)
    routine_map = {}
    for cpm in re.finditer(r"CP\s+(\d+)\s*:\s*JP\s+Z,(\w+)", body):
        routine_map[int(cpm.group(1))] = cpm.group(2)
    n_total = max(routine_map) + 2  # +1 0-index, +1 boss fallthrough entry

    THRESH = sym["SPAWN_THRESHOLDS"]
    SIMPLEY = sym["SPAWN_SIMPLE_Y_TABLE"]

    def tick(i):
        return out[THRESH + i * 2] | (out[THRESH + i * 2 + 1] << 8)

    def simpley(i):
        return out[SIMPLEY + i]

    simple_entries = [(tick(i), simpley(i)) for i in range(n_total)
                       if routine_map.get(i) == "SPAWN_SIMPLE"]
    boss_tick = tick(n_total - 1)
    return simple_entries, boss_tick


def build_schedule_block(simple_entries, boss_tick):
    n = len(simple_entries) + 1  # + boss
    ticks = [t for t, y in simple_entries] + [boss_tick]
    ys = [y for t, y in simple_entries] + [0]

    def db_lines(values, per_line=17):
        lines = []
        for i in range(0, len(values), per_line):
            lines.append("    DB " + ",".join(str(v) for v in values[i:i + per_line]))
        return "\n".join(lines)

    def dw_lines(values, per_line=17):
        lines = []
        for i in range(0, len(values), per_line):
            lines.append("    DW " + ",".join(str(v) for v in values[i:i + per_line]))
        return "\n".join(lines)

    zeros = [0] * n
    tables = "SPAWN_THRESHOLDS:\n" + dw_lines(ticks) + "\n\n"
    tables += "SPAWN_SIMPLE_Y_TABLE:\n" + db_lines(ys) + "\n\n"
    tables += "SPAWN_BASEY_TABLE:\n" + db_lines(zeros) + "\n\n"
    tables += "SPAWN_E3_OFFSET_TABLE:\n" + db_lines(zeros) + "\n\n"
    tables += "ENEMY6_ROW_TABLE:\n" + db_lines(zeros)

    dispatch = "SPAWN_SCHEDULE_CHECK:\n"
    dispatch += "    LD A,(SPAWN_NEXT_INDEX)\n"
    dispatch += f"    CP {n}\n"
    dispatch += "    RET NC\n"
    dispatch += "    LD H,0 : LD L,A\n"
    dispatch += "    ADD HL,HL\n"
    dispatch += "    LD DE,SPAWN_THRESHOLDS\n"
    dispatch += "    ADD HL,DE\n"
    dispatch += "    LD E,(HL) : INC HL : LD D,(HL)\n"
    dispatch += "    LD HL,(GAME_TICK)\n"
    dispatch += "    OR A\n"
    dispatch += "    SBC HL,DE\n"
    dispatch += "    RET C\n\n"
    dispatch += "    ; --- stage2-world test schedule: every entry is type=simple,\n"
    dispatch += "    ; --- filtered straight out of the real stage-1 schedule (same\n"
    dispatch += "    ; --- ticks/Y positions, just dropping every non-simple entry) -\n"
    dispatch += "    ; --- see build_stage2_world.py. No SSC_BUSY_E2-style guard is\n"
    dispatch += "    ; --- needed since there's no enemy2 in this schedule at all.\n"
    dispatch += "SSC_FIRE:\n"
    dispatch += "    LD A,(SPAWN_NEXT_INDEX)\n"
    dispatch += "    INC A\n"
    dispatch += "    LD (SPAWN_NEXT_INDEX),A\n"
    dispatch += "    DEC A\n"
    for i in range(n - 1):
        dispatch += f"    CP {i}   : JP Z,SPAWN_SIMPLE\n"
    dispatch += "    JP BOSS_SPAWN"

    return dispatch, tables, n


LETTER_PATTERNS = {
    "S": (0x3C, 0x66, 0x60, 0x3C, 0x06, 0x66, 0x3C, 0x00),
    "T": (0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00),
    "A": (0x18, 0x3C, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x00),
    "G": (0x3C, 0x66, 0x60, 0x6E, 0x66, 0x66, 0x3C, 0x00),
    "E": (0x7E, 0x60, 0x60, 0x7C, 0x60, 0x60, 0x7E, 0x00),
}
LETTER_ORDER = ["S", "T", "A", "G", "E"]
STAGE2_LETTER_BASE = 64  # confirmed-free code range (64-87), color group8


def patched_stage2_text():
    src_path = os.path.join(REPO, "src", "CYBER_GD_BOSS.asm")
    text = open(src_path, encoding="utf-8").read()

    # --- 1. spawn schedule: simple-only ---
    simple_entries, boss_tick = extract_simple_only_schedule()
    dispatch_block, tables_block, n = build_schedule_block(simple_entries, boss_tick)

    dispatch_start = text.index("SPAWN_SCHEDULE_CHECK:")
    # BOSS_CLEAR_DYNAMIC_ENEMIES: immediately follows the real dispatch
    # chain (with a blank line + comments in between) - anchor off that
    # instead of the bare string "JP BOSS_SPAWN", which also appears
    # earlier inside a comment describing the chain and would give a
    # much-too-short (and wrong) slice if matched first.
    boss_clear_pos = text.index("BOSS_CLEAR_DYNAMIC_ENEMIES:", dispatch_start)
    dispatch_end = text.rindex("JP BOSS_SPAWN", dispatch_start, boss_clear_pos) + len("JP BOSS_SPAWN")
    old_dispatch = text[dispatch_start:dispatch_end]
    assert old_dispatch.count("SSC_FIRE:") == 1
    assert old_dispatch.count("CP ") > 200, "dispatch slice looks too short - anchor mismatch"
    text = text.replace(old_dispatch, dispatch_block, 1)

    tables_start = text.index("SPAWN_THRESHOLDS:")
    tables_end = text.index("; --- Boss BG (nametable) graphics", tables_start)
    old_tables = text[tables_start:tables_end].rstrip("\n")
    text = text.replace(old_tables, tables_block, 1)

    # --- 2. STAGE2 letter glyphs, loaded right after the digit glyphs ---
    digit_load_anchor = "    LD HL,DIGIT_PATTERNS : LD DE,DIGIT_BASE*8 : LD BC,80 : CALL LDIRVM"
    assert text.count(digit_load_anchor) == 1
    letter_load_patch = digit_load_anchor + (
        "\n\n    ; --- [build_stage2_world.py] STAGE2 HUD label letters -----\n"
        "    LD HL,STAGE2_LETTER_PATTERNS : LD DE,STAGE2_LETTER_BASE*8 : LD BC,40 : CALL LDIRVM"
    )
    text = text.replace(digit_load_anchor, letter_load_patch, 1)

    # --- 3. HUD draw: "STAGE2" at row0 cols10-15, right after the initial score draw ---
    score_display_anchor = "    XOR A : LD (SCORE+2),A\n    CALL SCORE_DISPLAY"
    assert text.count(score_display_anchor) == 1
    hud_lines = ["    ; --- [build_stage2_world.py] permanent \"STAGE2\" HUD label ---"]
    for i, ch in enumerate(LETTER_ORDER):
        code = STAGE2_LETTER_BASE + i
        hud_lines.append(f"    XOR A : LD (ANIM_TMP_ROW),A")
        hud_lines.append(f"    LD A,{10+i} : LD (ANIM_TMP_COL),A")
        hud_lines.append(f"    LD A,{code} : LD (ANIM_TMP_VAL),A")
        hud_lines.append(f"    CALL WRITE_ANIM_CELL")
    hud_lines.append("    XOR A : LD (ANIM_TMP_ROW),A")
    hud_lines.append(f"    LD A,{10+len(LETTER_ORDER)} : LD (ANIM_TMP_COL),A")
    hud_lines.append(f"    LD A,{DIGIT_BASE_LITERAL}+2 : LD (ANIM_TMP_VAL),A")
    hud_lines.append("    CALL WRITE_ANIM_CELL")
    hud_patch = score_display_anchor + "\n\n" + "\n".join(hud_lines)
    text = text.replace(score_display_anchor, hud_patch, 1)

    # --- 4. STAGE2_LETTER_PATTERNS data, placed right by DIGIT_PATTERNS ---
    digit_patterns_anchor = "DIGIT_PATTERNS:"
    assert text.count(digit_patterns_anchor) == 1
    letters_data = "STAGE2_LETTER_BASE EQU 64\nSTAGE2_LETTER_PATTERNS:\n"
    for ch in LETTER_ORDER:
        bs = LETTER_PATTERNS[ch]
        letters_data += "    DB " + ",".join(f"{b:02X}h" for b in bs) + f"   ; {ch}\n"
    text = text.replace(digit_patterns_anchor, letters_data + digit_patterns_anchor, 1)

    # --- 5. color group8 (codes 64-71, covers our 5 new letters at 64-68):
    #     was 0D3h ("shot-green") but codes 64-71 have no pattern data
    #     loaded (confirmed free range) so nothing currently visible
    #     uses that color - safe to repoint at a readable white/black,
    #     matching the digit HUD's own style. ---
    color_anchor = "DB 44h,0D4h,0D3h,0DFh,0DAh,0F4h,0FFh,0F3h,0FAh,084h"
    assert text.count(color_anchor) == 1
    color_patch = color_anchor.replace("0D3h", "0F1h", 1)
    text = text.replace(color_anchor, color_patch, 1)

    return text, n


DIGIT_BASE_LITERAL = "DIGIT_BASE"


def assemble_stage2_world():
    text, n = patched_stage2_text()
    a = Assembler(text)
    out = a.assemble()
    bank2 = bytearray([0xFF] * 0x4000)
    bank3 = bytearray([0xFF] * 0x4000)
    for addr, val in out.items():
        if 0x4000 <= addr <= 0x7FFF:
            bank2[addr - 0x4000] = val
        elif 0x8000 <= addr <= 0xBFFF:
            bank3[addr - 0x8000] = val
        else:
            raise Exception(f"stage2 byte at unexpected address {addr:04x}")
    return bank2, bank3, a.symtab, n


if __name__ == "__main__":
    bank2, bank3, sym, n = assemble_stage2_world()
    print(f"stage2 world assembled: bank2 {len(bank2)}B, bank3 {len(bank3)}B")
    print(f"schedule entries: {n} (all simple except the last, which is boss)")
    print(f"INIT = {sym['INIT']:04x}  MAINLOOP = {sym['MAINLOOP']:04x}")
