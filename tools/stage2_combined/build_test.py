"""Assembles the combined terrain + tank test: the stage2_terrain
scroller (own INIT/MAINLOOP engine) with the tank sprite sitting on
top of it. Border-color diagnostic checkpoints through INIT (see the
README) since the tank-only test reportedly froze on real hardware
with no clue where.

Now a real ASCII16 MegaROM (bank0=page1/4000h-7FFFh, bank1=page2/
8000h-BFFFh, RAM-trampoline bank-select in INIT), not a flat 32KB
image - "フリーズはしてないがグリッチ ボーダーはブラックだな...
ASCII16の本番形式でやってみろ 64KBだからな": once content grew past
16KB, the flashcart being tested on evidently can't boot a plain
linear image at all (confirmed on real hardware: didn't even reach
INIT's own first instruction), the same real, production mechanism
`tools/bankswitch_poc/build_full_rom.py` already uses for the shipped
game. Since this file has no genuine second PHASE of content the way
the main game's stage1->stage2 transition does - just needs more than
16KB total for one continuous program - bank1 is selected exactly
once, at boot, and left selected permanently; unlike bankswitch_poc's
own multi-bank build, there's no later mid-game switch to test.
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "tools"))
sys.path.insert(0, os.path.join(REPO, "tools", "stage2_terrain"))
sys.path.insert(0, os.path.join(REPO, "tools", "stage2_tank"))

import terrain_gen  # noqa: E402
import tank_gen  # noqa: E402
import bullet_gen  # noqa: E402
import enemy_gen  # noqa: E402
import bigzum_gen  # noqa: E402
import flyer_gen  # noqa: E402
import etank_gen  # noqa: E402
import sasapi_gen  # noqa: E402
import sasapi_hand_gen  # noqa: E402
import horming_gen  # noqa: E402
import thunder_gen  # noqa: E402
import sbeam_gen  # noqa: E402
import ebullet_gen  # noqa: E402
import etankbullet_gen  # noqa: E402
import mine_gen  # noqa: E402
import flyerlaser_gen  # noqa: E402
import ending_text_gen  # noqa: E402
import ending_image_gen  # noqa: E402
from mini_z80asm import Assembler  # noqa: E402


def combined_text():
    """The raw, unpatched source text (body + generated sprite/table
    data) - split out from assemble() so build_full_rom.py's "Comb"
    build can patch it (retargeting the bank-select embedded in this
    file's own INIT, see that file) before assembling, without
    duplicating the table-gen imports/concatenation here."""
    body = open(os.path.join(HERE, "combined_test.asm")).read()
    tables = (terrain_gen.emit_asm_tables() + "\n" + tank_gen.emit_asm_tables()
              + "\n" + bullet_gen.emit_asm_tables() + "\n" + enemy_gen.emit_asm_tables()
              + "\n" + bigzum_gen.emit_asm_tables() + "\n" + flyer_gen.emit_asm_tables()
              + "\n" + etank_gen.emit_asm_tables() + "\n" + sasapi_gen.emit_asm_tables()
              + "\n" + sasapi_hand_gen.emit_asm_tables() + "\n" + horming_gen.emit_asm_tables()
              + "\n" + thunder_gen.emit_asm_tables() + "\n" + sbeam_gen.emit_asm_tables()
              + "\n" + ebullet_gen.emit_asm_tables() + "\n" + etankbullet_gen.emit_asm_tables()
              + "\n" + mine_gen.emit_asm_tables() + "\n" + flyerlaser_gen.emit_asm_tables()
              + "\n" + ending_text_gen.emit_asm_tables() + "\n" + ending_image_gen.emit_asm_tables())
    return gfx2_relocate(body + "\n" + tables + "\n")


# (2026-09-24、"Stage2も進めて"): INITで1回だけVRAMへ送る絵柄データを
# ゲームオーバーバンクの後半へ移す(combined_test.asmのGFX2_BLOB_START
# 区画参照)。GFX2_MOVEはINIT以外から読まれないDBブロック(ROMから消す)、
# GFX2_DUPはINIT以外からも読むブロック(ROMに残したまま"G2D_"付きの
# 複製をGFX2区画へ置く)。32x32の4分割ブロックは_TL/_TR/_BL/_BRを並び順
# のまま移す(MIRROR_32X32_POSE_TO_VRAMが128byte連続で読むため)。
def _quad(name):
    base = name[:-3]
    return [base + s for s in ("_TL", "_TR", "_BL", "_BR")]


GFX2_MOVE = (["TERRAIN_PATTERNS", "TERRAIN_COLORDATA"]
             + _quad("TANK_TANKF_TL") + _quad("TANK_TANKFGAP_TL") + _quad("TANK_TANKUGAP_TL")
             + ["BULLET_F_PATTERN0", "BULLET_F_PATTERN1", "BULLET_F_PATTERN2",
                "BULLET_F_L_PATTERN0", "BULLET_F_L_PATTERN1", "BULLET_F_L_PATTERN2",
                "BULLET_U_PATTERN", "BULLET_U_L_PATTERN", "ENEMY_ZACOII", "ENEMY_ZUM"]
             + _quad("BIGZUM_BIGZUMP_TL") + _quad("FLYER_TL")
             + ["HORMING_BG_SL_PATTERN", "HORMING_BG_DL_PATTERN", "HORMING_BG_DOWN_PATTERN",
                "HORMING_BG_DR_PATTERN", "HORMING_BG_SR_PATTERN", "THUNDER_TILES", "THUNDERS_TILE",
                "EBULLET_SPRITE", "ETANK_BULLET_PATTERN", "MINE1_PATTERN", "MINE2_PATTERN",
                "FLYER_LASER_PATTERN",
                "ROCK_COLOR_SWAPPED_PATCH", "CLOUD_A_PATTERN", "CLOUD_B_PATTERN", "HUD_ZERO8",
                "SKYSAND_PATTERN", "TERRAIN_ROW_SKYSAND", "TERRAIN_ROW_SAND", "LIFE_PATTERN",
                "DIGIT_PATTERNS_LOCAL", "BOOSTER1_SPRITE", "BOOSTER2_SPRITE"])
GFX2_DROP = ["TERRAIN_BLANK_ROW"]  # 0が768byte - INITはFILVRMで埋める
GFX2_DUP = (_quad("TANK_TANKUP_TL") + _quad("BIGZUM_BIGZUM_TL")
            + ["BULLET_U_SPRITE0", "BULLET_U_SPRITE0_L", "EXPLOSION_PATTERN",
               "HUD_BLACKROW32", "SASAPI_HAND_COLOR8"])
GFX2_SCRATCH = 0xC000   # combined_test.asmのGFX2_SCRATCH
GFX2_BANK_OFFSET = 0x2000  # ゲームオーバーバンク内の置き場所(window BでA000h)

_LBL_RE = re.compile(r"^([A-Z_][A-Z0-9_]*):\s*(;.*)?$")
_DATA_RE = re.compile(r"^\s*(DB|DW|DS)\b", re.I)


def _data_unit(lines, name):
    """name:の行から、次のラベル行の手前までのDB/DW/DS行(途中の空行・
    コメントを含み、末尾の空行・コメントは含まない)の範囲を返す。"""
    idx = [i for i, l in enumerate(lines) if l is not None and _LBL_RE.match(l)
           and _LBL_RE.match(l).group(1) == name]
    assert len(idx) == 1, f"GFX2: label {name} not found exactly once"
    i = idx[0]
    j = i + 1
    last = i
    while j < len(lines):
        l = lines[j]
        if l is None or _LBL_RE.match(l):
            break
        c = l.split(";")[0].strip()
        if c == "":
            j += 1
            continue
        if _DATA_RE.match(l):
            last = j
            j += 1
            continue
        break
    assert last > i, f"GFX2: {name} has no data lines"
    return i, last + 1


def gfx2_relocate(text):
    lines = text.split("\n")
    moved = []
    for name in GFX2_DUP:
        a, b = _data_unit(lines, name)
        moved.append("G2D_" + lines[a].lstrip())
        moved.extend(lines[a + 1:b])
    for name in GFX2_MOVE + GFX2_DROP:
        a, b = _data_unit(lines, name)
        if name in GFX2_MOVE:
            moved.extend(lines[a:b])
        for k in range(a, b):
            lines[k] = None
    lines = [l for l in lines if l is not None]
    end = [i for i, l in enumerate(lines) if l.startswith("GFX2_BLOB_END:")]
    assert len(end) == 1
    lines[end[0]:end[0]] = moved
    return "\n".join(lines)


def gfx2_blob(out):
    """アセンブル結果からGFX2区画(C000h〜)を取り出す。"""
    addrs = [a for a in out if a >= GFX2_SCRATCH]
    assert addrs, "GFX2 blob missing"
    size = max(addrs) - GFX2_SCRATCH + 1
    assert size <= 0x4000 - GFX2_BANK_OFFSET, f"GFX2 blob too large ({size} bytes)"
    return bytes(out.get(GFX2_SCRATCH + i, 0xFF) for i in range(size))


def gfx2_bank(blob, base=None):
    """ゲームオーバーバンク(base、無ければ0xFF埋め)のオフセット2000hへ
    GFX2区画を入れた16KBを返す。"""
    bank = bytearray(base) if base is not None else bytearray([0xFF] * 0x4000)
    assert all(b == 0xFF for b in bank[GFX2_BANK_OFFSET:]), \
        "gameover bank already uses the GFX2 area (offset 2000h-)"
    bank[GFX2_BANK_OFFSET:GFX2_BANK_OFFSET + len(blob)] = blob
    return bank


def assemble():
    text = combined_text()
    asm = Assembler(text)
    out = asm.assemble()
    return out, asm.symtab, text


def build_banks(out):
    """Splits the flat address->byte dict from assemble() into bank0
    (page1, 4000h-7FFFh) and bank1 (page2, 8000h-BFFFh) - same 0xFF-
    padded-unused-space convention as bankswitch_poc's own
    assemble_to_bytes(). Raises if anything landed outside 4000h-
    BFFFh (the 32KB-per-bank-pair budget)."""
    bank0 = bytearray([0xFF] * 0x4000)
    bank1 = bytearray([0xFF] * 0x4000)
    for addr, val in out.items():
        if addr >= GFX2_SCRATCH:
            continue  # GFX2区画(gfx2_blob()がゲームオーバーバンクへ入れる)
        if 0x4000 <= addr <= 0x7FFF:
            bank0[addr - 0x4000] = val
        elif 0x8000 <= addr <= 0xBFFF:
            bank1[addr - 0x8000] = val
        else:
            raise Exception(f"address {addr:04X}h outside 4000h-BFFFh (bank0+bank1 budget exceeded)")
    bank1 = _Bank(bank1)
    bank1.gfx2_blob = gfx2_blob(out)
    return bank0, bank1


class _Bank(bytearray):
    """bank1にGFX2区画を持たせてBankedMemへ渡すためだけの入れ物。"""
    gfx2_blob = None


class BankedMem:
    """ASCII16-style mapper emulation for testing in z80emu.py - a
    plain flat bytearray would let the trampoline's own write to
    6000h/7000h silently corrupt whatever live program byte happens to
    sit at that address (confirmed: 0x7000 held a real opcode byte in
    this file's own current layout), producing misleading results.
    Writes to `portA`(6000h)/`portB`(7000h) select which bank is
    currently visible at page1/page2; any other write within 4000h-
    BFFFh is silently ignored (real ROM, matches actual cartridge
    behavior); everything outside 4000h-BFFFh is flat, directly-
    writable RAM (also where the BIOS's own low-memory area lives,
    same as z80emu.py's own bios_call() stubs already assume). Same
    shape as bankswitch_poc's own BankedMem (run_poc.py/verify_full.py)
    - banksB index0 is an unused blank placeholder purely so "A=1
    selects index1" lines up with the real bank-select convention this
    file's own INIT actually uses.
    """
    def __init__(self, bank0, bank1, portA=0x6000, portB=0x7000):
        self.flat = bytearray(0x10000)
        self.banksA = [bank0]
        # index2: real BGM data bank (round40, tools/bgm_data/bgm_bank_gen.py)
        # - INIT_BGM selects A=2 for this standalone numbering (patched to
        # A=6 in the Comb build, see build_full_rom.py) before copying the
        # period table + this stage's song into RAM, so any test exercising
        # a real INIT trace now needs genuine content here, not another
        # 0xFF-filled placeholder.
        bgm_spec = importlib.util.spec_from_file_location(
            "bgm_bank_gen", os.path.join(REPO, "tools", "bgm_data", "bgm_bank_gen.py"))
        bgm_mod = importlib.util.module_from_spec(bgm_spec)
        bgm_spec.loader.exec_module(bgm_mod)
        bgm_bank, _ = bgm_mod.build_bank()
        self.banksB = [bytearray([0xFF] * 0x4000), bank1, bytearray(bgm_bank)]
        # index3: ゲームオーバーバンク(standalone番号3)。INITのGFX2_LOAD_LIST
        # がwindow Bをここへ切り替えて絵柄を読む(2026-09-24)。
        blob = getattr(bank1, "gfx2_blob", None)
        if blob is not None:
            self.banksB.append(gfx2_bank(blob))
        self.bankA = 0
        self.bankB = 0
        self.portA = portA
        self.portB = portB
        self.switch_log = []

    def __getitem__(self, addr):
        addr &= 0xFFFF
        if 0x4000 <= addr <= 0x7FFF:
            return self.banksA[self.bankA][addr - 0x4000]
        if 0x8000 <= addr <= 0xBFFF:
            return self.banksB[self.bankB][addr - 0x8000]
        return self.flat[addr]

    def __setitem__(self, addr, val):
        addr &= 0xFFFF
        val &= 0xFF
        if addr == self.portA:
            self.bankA = val % len(self.banksA)
            self.switch_log.append(("A", val, self.bankA))
            return
        if addr == self.portB:
            self.bankB = val % len(self.banksB)
            self.switch_log.append(("B", val, self.bankB))
            return
        if 0x4000 <= addr <= 0xBFFF:
            return  # ROM: writes silently ignored
        self.flat[addr] = val


def main():
    out, sym, text = assemble()
    lo, hi = min(out), max(out)
    bank0, bank1 = build_banks(out)
    rom32 = bytes(bank0) + bytes(bank1)
    # doubled to 64KB - same real-hardware-required convention as
    # bankswitch_poc/build_rom.py (a real flashcart mirrored a 32KB
    # image instead of decoding real ASCII16 banks until doubled to a
    # "regulation" size for its own mapper auto-detection).
    rom = rom32 + rom32
    # "またお前は忘れてるがファイル名に[ASCII16]を含めろと過去に指示し
    # てる リセットはそのせいだった" - real-hardware testing was never
    # actually the method here; verification is via WebMSX, which
    # auto-detects the mapper type from the FILENAME (matching the real
    # shipped ROM's own "CYBER SHMUP [ASCII16].rom" convention - see
    # bankswitch_poc/build_full_rom.py), not from file content/size the
    # way this session had been assuming throughout the whole page2-
    # mapping investigation. Without the tag, WebMSX evidently fell
    # back to some other ROM-type guess for both the 32KB and 64KB
    # builds - explaining the instant reset on the 64KB file (wrong
    # type for that size) and, per direct confirmation, the SAME
    # glitch on both the pre- and post-ASCII16 versions (meaning the
    # bank-switch code was very likely never actually being exercised
    # at all before now - the glitch itself is apparently unrelated to
    # any of the page2/bank-switch work and still needs its own real
    # root cause once this file is finally loaded under its correct
    # mapper type for the first time).
    # "ここで貼るROMファイル名を Stage1はCyberS S1.ascii16k.rom Stage2は
    # CyberS S2.ascii16k.rom として出力" (round28) - renamed from
    # "combined_test [ASCII16].rom". Still contains "ascii16" as a
    # substring (just lowercase, no brackets, trailing "k") - per this
    # file's own comment history just above, WebMSX's mapper auto-
    # detection keys off the filename itself, not ROM content/size, so
    # this rename needs the same real-hardware/WebMSX confirmation any
    # filename change here always has before trusting it.
    rom_path = os.path.join(HERE, "CyberS S2.ascii16k.rom")
    with open(rom_path, "wb") as f:
        f.write(rom)
    print(f"assembled {lo:04X}h-{hi:04X}h ({hi-lo+1} bytes across bank0+bank1), wrote {rom_path}: {len(rom)} bytes (doubled)")
    print("INIT =", hex(sym["INIT"]), "MAINLOOP =", hex(sym["MAINLOOP"]))
    return out, sym, text


if __name__ == "__main__":
    main()
