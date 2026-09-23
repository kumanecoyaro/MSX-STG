"""Stage1 INIT初期化漏れ検出(2026-09-23、監査): RAM(0xC000-0xF37F)を0x00で
埋めた場合と0xFFで埋めた場合の両方からINITを実行し、同じ入力で進めたゲーム
状態(GAME_TICK/SCORE/自機座標/各生存数/ネームテーブル/スプライト属性)が全フレーム
一致することを確認する。ずれたら、INITで初期化されていない値に依存している。
Titleが実機で事前コピーするデータ(BGM・ボス絵柄・EBUZ2テーブル・フォント)と
GAMEOVER_ENABLED、意図的な乱数カウンタDFL_RNGは両方で同じ値にそろえる。
使い方: python3 tools/verify_stage1_ram_poison.py [フレーム数(既定2500、ボス戦まで
なら17000程度)]
"""
import sys, json, os
T=os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0,T); sys.path.insert(0,T+'/bgm_data')
from mini_z80asm import Assembler
from z80emu import Z80
text=open(os.path.join(T,'..','src','CYBER SHMUP.asm'),encoding='utf-8').read()
A=Assembler(text); out=A.assemble(); sym=A.symtab
mem0=bytearray(65536)
for a,v in out.items(): mem0[a&0xFFFF]=v&0xFF
ns={}; exec(open(T+'/verify_ship_entry.py',encoding='utf-8').read().split('def fresh():')[0].replace("__file__","'"+T+"/verify_ship_entry.py'"),ns)
blob=ns['_real_mgf_compressed']
bank=open(T+'/bgm_data/bgm_bank.bin','rb').read()
import patch_ebuz2_mk2 as pe
def boot(fill):
    m=bytearray(mem0)
    for a in range(0xC000,0xF380): m[a]=fill       # 変数領域(スタック上端まで)を汚染
    z=Z80(m)
    # Titleが実際にコピーするデータ(実機でも必ず正しい値)
    for hl,de,bc in [(0x8000,0xC000,0x78),(0x8078,0xC078,0x628),(0x8E32,0xC910,0x32E),(0x931B,0xCC42,0x10D),(0x9428,0xCD5B,0x32),(0xBD0A,0xCD8D,0x122),(0xBE2C,0xD0C0,0xE3),(0xBF0F,0xD20A,0x48),(0xBF57,0xD28A,0x72)]:
        for i in range(bc): z.wr(de+i,bank[hl-0x8000+i])
    for name,data in zip(('EBUZ2_SCRIPT_TABLE','EBUZ2_ALTLOOP_TABLE','EBUZ2_STOPSEQ_TABLE'),pe.build_tables(sym)):
        for i,b in enumerate(data): z.wr(sym[name]+i,b)
    for i,b in enumerate(blob): z.wr(sym['STAGE1_MISSION_GAMEOVER_FONT']+i,b)
    z.wr(sym['GAMEOVER_ENABLED'],0)   # Titleが設定する値(テスト用に無敵)
    z.wr(sym['DFL_RNG'],0x5A)          # 乱数カウンタは両実走で同じ種に(意図的な乱数、バグではない)
    z.pc=sym['INIT']
    for _ in range(8000000):
        if z.pc==sym['MAINLOOP']: break
        z.step()
    return z
zs=[boot(0x00),boot(0xFF)]
ML=sym['MAINLOOP']
def state(z):
    g=lambda n,k=1: tuple(z.rd(sym[n]+i) for i in range(k))
    return (g('GAME_TICK',2),g('SCORE',3),g('PLAYERX'),g('PLAYERY'),g('SPAWN_NEXT_INDEX',2),g('ENEMY3_ACTIVE_COUNT'),g('ENEMY6_ACTIVE_COUNT'),
            g('EBUZ2_ACT'),g('BOSS_STATE'),g('BARRIER_HP'),bytes(z.vram[0x1800:0x1B00]),bytes(z.vram[0x1B00:0x1B80]))
first=None
NFR=int(sys.argv[1]) if len(sys.argv)>1 else 2500
for f in range(NFR):
    for z in zs:
        z.sim_trig_a=True; z.sim_dir=[1,5][(f//60)%2]
        z.step()
        n=0
        while z.pc!=ML and n<3000000: z.step(); n+=1
    s0,s1=state(zs[0]),state(zs[1])
    if s0!=s1:
        names=['GAME_TICK','SCORE','PLAYERX','PLAYERY','SPAWN_NEXT_INDEX','E3_COUNT','E6_COUNT','EBUZ2_ACT','BOSS_STATE','BARRIER_HP','NAMETABLE','SPRATR']
        diff=[names[i] for i in range(len(s0)) if s0[i]!=s1[i]]
        print('DIVERGE at frame',f,'fields',diff)
        if 'NAMETABLE' in diff:
            d=[i for i in range(768) if s0[10][i]!=s1[10][i]]; print('  nametable cells differ:',[(i//32,i%32) for i in d[:10]])
        if 'SPRATR' in diff:
            d=[i for i in range(128) if s0[11][i]!=s1[11][i]]; print('  sprite attr bytes differ:',d[:16])
        first=f; break
    if f%2000==0: print('frame',f,'identical so far',flush=True)
print('END', 'frames', NFR, 'first divergence', first)
sys.exit(1 if first is not None else 0)
