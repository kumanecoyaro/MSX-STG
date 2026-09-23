"""Stage1: スケジュールの4表(SPAWN_SIMPLE_Y/SPAWN_BASEY/SPAWN_E3_OFFSET/ENEMY6_ROW、
各341byte)を1本にまとめた(2026-09-23、ROM予算)ことの等価性検証。

各スケジュールエントリについて、現在のソースで実際のSSC_FIREを走らせてどのSPAWN_*へ
振り分けられるかを調べ、そのハンドラが読む表(SIMPLE→Y、E2/E4/E4B→BASEY、E3_WAVE→
E3_OFFSET、E6→ROW)の旧値(まとめる前のコミットをアセンブルして取得)と、まとめた表の
値が一致することを全エントリで確認する。ハンドラ自身のコードは変えていないので、
これで挙動が同じであることが言える。
"""
import os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mini_z80asm import Assembler
from z80emu import Z80

REPO = os.path.join(HERE, '..')
BEFORE_MERGE_COMMIT = '67a2151'   # 4表がまだ別々だった最後のコミット
HANDLER_TABLE = {'SPAWN_SIMPLE': 'SPAWN_SIMPLE_Y_TABLE', 'SPAWN_E2': 'SPAWN_BASEY_TABLE',
                 'SPAWN_E4': 'SPAWN_BASEY_TABLE', 'SPAWN_E4B': 'SPAWN_BASEY_TABLE',
                 'SPAWN_E3_WAVE': 'SPAWN_E3_OFFSET_TABLE', 'SPAWN_E6': 'ENEMY6_ROW_TABLE'}
ok, fail = [], []
def check(label, cond):
    (ok if cond else fail).append(label); print(("PASS " if cond else "FAIL "), label)

def build(text):
    a = Assembler(text); out = a.assemble()
    mem = bytearray(65536)
    for k, v in out.items(): mem[k & 0xFFFF] = v & 0xFF
    return mem, a.symtab

new_text = open(os.path.join(REPO, 'src', 'CYBER SHMUP.asm'), encoding='utf-8').read()
old_text = subprocess.run(['git', 'show', f'{BEFORE_MERGE_COMMIT}:src/CYBER SHMUP.asm'], cwd=REPO,
                          capture_output=True, check=True).stdout.decode('utf-8')
new_mem, new_sym = build(new_text)
old_mem, old_sym = build(old_text)
N = int(re.search(r"LD HL,\(SPAWN_NEXT_INDEX\)\n    LD DE,(\d+)", new_text).group(1))
N_old = int(re.search(r"LD HL,\(SPAWN_NEXT_INDEX\)\n    LD DE,(\d+)", old_text).group(1))
check(f"same schedule length before/after the merge ({N})", N == N_old)
check("the other three table names are now aliases of the one merged table",
      new_sym['SPAWN_BASEY_TABLE'] == new_sym['SPAWN_E3_OFFSET_TABLE'] == new_sym['ENEMY6_ROW_TABLE']
      == new_sym['SPAWN_SIMPLE_Y_TABLE'])
check("old build really had four separate tables",
      len({old_sym[t] for t in set(HANDLER_TABLE.values())}) == 4)

class Traced:
    """z80emuの全メモリ読み出しはZ80.rd経由なので、memを差し替えて読み出し番地を記録する"""
    def __init__(self, data, lo, hi):
        self.d = data; self.lo = lo; self.hi = hi; self.reads = []
    def __getitem__(self, a):
        if self.lo <= a < self.hi: self.reads.append(a)
        return self.d[a]
    def __setitem__(self, a, v): self.d[a] = v

def table_reads(mem, sym, lo, hi, i):
    """スケジュールindex iでSSC_FIREを実際に実行し(SPAWN_*まで含めて)、[lo,hi)の読み出しを返す"""
    tm = Traced(bytearray(mem), lo, hi)
    z = Z80(tm)
    z.wr(sym['SPAWN_NEXT_INDEX'], i & 255); z.wr(sym['SPAWN_NEXT_INDEX'] + 1, i >> 8)
    z.sp = 0xF000; z.wr(0xF000, 0); z.wr(0xF001, 0)
    z.pc = sym['SSC_FIRE']
    for _ in range(200000):
        if z.pc == 0: break
        z.step()
    return tm.reads

old_lo = min(old_sym[n] for n in set(HANDLER_TABLE.values()))
old_hi = max(old_sym[n] for n in set(HANDLER_TABLE.values())) + N_old
base = new_sym['SPAWN_SIMPLE_Y_TABLE']
bad = []; n_read = 0
for i in range(N):
    nr = table_reads(new_mem, new_sym, base, base + N, i)
    orr = table_reads(old_mem, old_sym, old_lo, old_hi, i)
    if not nr and not orr:
        continue                                   # 表を読まないハンドラ(Ebuz系等)
    n_read += 1
    if nr != [base + i] * len(nr) or len(nr) != len(orr) or \
       [new_mem[a] for a in nr] != [old_mem[a] for a in orr]:
        bad.append((i, [hex(x) for x in nr], [hex(x) for x in orr]))
check(f"every schedule entry, actually executed through SSC_FIRE and its SPAWN_* handler: the new build reads "
      f"exactly its own index in the merged table and gets the same byte(s) the old build read from its own "
      f"separate table ({n_read} entries read a table) {bad[:3]}", not bad and n_read > 300)
print(f"\n{len(ok)} passed, {len(fail)} failed")
sys.exit(1 if fail else 0)
