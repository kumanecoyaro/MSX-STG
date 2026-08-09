import sys

class Z80:
    def __init__(self, mem):
        self.mem = mem  # bytearray 65536
        self.a=0;self.f=0;self.b=0;self.c=0;self.d=0;self.e=0;self.h=0;self.l=0
        self.ix=0;self.iy=0;self.sp=0;self.pc=0
        self.iff1=False
        self.halted=False
        self.vram = bytearray(16384)
        self.vdp_addr=0
        self.vdp_write_mode=False
        self.vdp_latch=None
        self.vram_writes_log = []  # (addr,val,pc)
        self.io_out_log = []
        # --- T-state (cycle) accounting ---
        # self.tstates: running total, incremented by every step()/step_xx()
        # call with the real Z80 timing for the instruction just executed
        # (branch-dependent costs like RET cc/JR cc/DJNZ/CALL cc/LDIR use
        # their actual taken/not-taken or repeat-count timing, not a
        # worst-case guess).
        # self.tstates_indexed: subset of the above spent inside DD/FD-
        # prefixed (IX/IY) instructions - every (IX+d)/(IY+d) access, plus
        # LD IX,nn / PUSH IX / POP IX etc, all costed at their real (higher)
        # indexed timing. Use this to quantify "how much of the frame goes
        # to IX/IY overhead" for a given call path.
        # self.tstates_pushpop: subset spent in PUSH/POP (BC/DE/HL/AF/IX/IY),
        # including the common HL->IX transfer idiom (PUSH HL:POP IX).
        # self.instr_count / self.instr_count_indexed: matching instruction
        # counts, for computing per-instruction averages.
        self.tstates = 0
        self.tstates_indexed = 0
        self.tstates_pushpop = 0
        self.tstates_nop = 0
        self.instr_count = 0
        self.instr_count_indexed = 0

    def stats(self):
        return {
            'tstates': self.tstates,
            'tstates_indexed': self.tstates_indexed,
            'tstates_pushpop': self.tstates_pushpop,
            'tstates_nop': self.tstates_nop,
            'instr_count': self.instr_count,
            'instr_count_indexed': self.instr_count_indexed,
        }

    def reset_stats(self):
        self.tstates = 0
        self.tstates_indexed = 0
        self.tstates_pushpop = 0
        self.tstates_nop = 0
        self.instr_count = 0
        self.instr_count_indexed = 0

    def bios_call(self, target):
        # intercept known BIOS routines instead of executing into unmapped ROM
        if target == 0x005C:  # LDIRVM: HL=src(RAM), DE=dest(VRAM), BC=count
            hl=self.hl(); de=self.de(); bc=self.bc()
            for i in range(bc):
                v = self.rd((hl+i)&0xFFFF)
                vaddr = (de+i)&0x3FFF
                self.vram[vaddr]=v
                self.vram_writes_log.append((vaddr,v,self.pc))
            self.sethl((hl+bc)&0xFFFF); self.setde((de+bc)&0xFFFF); self.setbc(0)
            return True
        if target == 0x006F:  # INIT32: VDP mode setup, no-op for our tracing
            return True
        if target == 0x0047:  # WRTVDP: C=reg,B=data - no-op (register state not tracked)
            return True
        if target == 0x00D5:  # GTSTCK: A=id -> A=0 (centered/no input)
            self.a = 0
            return True
        if target == 0x00D8:  # GTTRIG: A=id -> simulated fire button
            self.a = 0xFF if getattr(self,'sim_fire',False) else 0
            return True
        return False

    # flags: bit0 C,1 N,2 PV,3 -,4 H,5 -,6 Z,7 S
    def setZ(self,v):
        if v&0xFF==0: self.f|=0x40
        else: self.f&=~0x40
    def setS(self,v):
        if v&0x80: self.f|=0x80
        else: self.f&=~0x80

    def rd(self,addr): return self.mem[addr&0xFFFF]
    def wr(self,addr,val): self.mem[addr&0xFFFF]=val&0xFF

    def fetch(self):
        b=self.rd(self.pc); self.pc=(self.pc+1)&0xFFFF; return b
    def fetch16(self):
        lo=self.fetch(); hi=self.fetch(); return lo|(hi<<8)

    def push(self,val):
        self.sp=(self.sp-2)&0xFFFF
        self.wr(self.sp,val&0xFF)
        self.wr(self.sp+1,(val>>8)&0xFF)
    def pop(self):
        lo=self.rd(self.sp); hi=self.rd(self.sp+1)
        self.sp=(self.sp+2)&0xFFFF
        return lo|(hi<<8)

    def getr8(self,idx):
        return [self.b,self.c,self.d,self.e,self.h,self.l,None,self.a][idx]
    def setr8(self,idx,val):
        val&=0xFF
        if idx==0: self.b=val
        elif idx==1: self.c=val
        elif idx==2: self.d=val
        elif idx==3: self.e=val
        elif idx==4: self.h=val
        elif idx==5: self.l=val
        elif idx==7: self.a=val

    def hl(self): return (self.h<<8)|self.l
    def sethl(self,v): self.h=(v>>8)&0xFF; self.l=v&0xFF
    def de(self): return (self.d<<8)|self.e
    def setde(self,v): self.d=(v>>8)&0xFF; self.e=v&0xFF
    def bc(self): return (self.b<<8)|self.c
    def setbc(self,v): self.b=(v>>8)&0xFF; self.c=v&0xFF

    def vdp_out(self, port, val):
        if port==0x99:
            if self.vdp_latch is None:
                self.vdp_latch = val
            else:
                lo = self.vdp_latch; hi = val
                self.vdp_latch = None
                if hi & 0x80:
                    # register write (VDP register set), bits0-2 select register (for basic ops)
                    pass
                else:
                    self.vdp_addr = (lo | ((hi&0x3F)<<8)) & 0x3FFF
                    self.vdp_write_mode = bool(hi & 0x40)
        elif port==0x98:
            self.vram[self.vdp_addr] = val & 0xFF
            self.vram_writes_log.append((self.vdp_addr, val&0xFF, self.pc))
            self.vdp_addr = (self.vdp_addr+1) & 0x3FFF
        self.io_out_log.append((port,val,self.pc))

    def vdp_in(self, port):
        if port==0x98:
            v = self.vram[self.vdp_addr]
            self.vdp_addr = (self.vdp_addr+1) & 0x3FFF
            return v
        elif port==0x99:
            return 0x00  # status: no flags set
        return 0xFF

    def step(self):
        pc0 = self.pc
        self.instr_count += 1
        op = self.fetch()
        if op == 0x00: self.tstates += 4; self.tstates_nop += 4  # NOP
        elif op == 0x76:  # HALT
            self.tstates += 4
            self.halted = True
            return
        elif op == 0xF3: self.iff1=False; self.tstates += 4  # DI
        elif op == 0xFB: self.iff1=True; self.tstates += 4   # EI
        elif op == 0xC9:  # RET
            self.pc = self.pop(); self.tstates += 10
        elif op in (0xC0,0xC8,0xD0,0xD8,0xE0,0xE8,0xF0,0xF8):  # RET cc
            cc = (op>>3)&7
            if self.check_cc(cc): self.pc = self.pop(); self.tstates += 11
            else: self.tstates += 5
        elif op == 0xCD:  # CALL nn
            target = self.fetch16()
            self.tstates += 17
            if self.bios_call(target):
                pass
            else:
                self.push(self.pc)
                self.pc = target
        elif op in (0xC4,0xCC,0xD4,0xDC,0xE4,0xEC,0xF4,0xFC):
            cc=(op>>3)&7
            target=self.fetch16()
            if self.check_cc(cc):
                self.push(self.pc); self.pc=target; self.tstates += 17
            else:
                self.tstates += 10
        elif op == 0xC3:
            self.pc = self.fetch16(); self.tstates += 10
        elif op in (0xC2,0xCA,0xD2,0xDA,0xE2,0xEA,0xF2,0xFA):
            cc=(op>>3)&7
            target=self.fetch16()
            self.tstates += 10
            if self.check_cc(cc): self.pc=target
        elif op == 0x18:  # JR
            d = self.fetch();
            if d>127: d-=256
            self.pc = (self.pc+d)&0xFFFF
            self.tstates += 12
        elif op in (0x20,0x28,0x30,0x38):
            cc = {0x20:'NZ',0x28:'Z',0x30:'NC',0x38:'C'}[op]
            d=self.fetch()
            if d>127: d-=256
            take = {'NZ': not (self.f&0x40), 'Z': bool(self.f&0x40), 'NC': not(self.f&0x01), 'C': bool(self.f&0x01)}[cc]
            if take:
                self.pc=(self.pc+d)&0xFFFF
                self.tstates += 12
            else:
                self.tstates += 7
        elif op == 0x10:  # DJNZ
            d=self.fetch()
            if d>127: d-=256
            self.b=(self.b-1)&0xFF
            if self.b!=0:
                self.pc=(self.pc+d)&0xFFFF
                self.tstates += 13
            else:
                self.tstates += 8
        elif op == 0xD3:  # OUT (n),A
            n=self.fetch()
            self.vdp_out(n, self.a) if n in (0x98,0x99) else None
            self.tstates += 11
        elif op == 0xDB:  # IN A,(n)
            n=self.fetch()
            self.a = self.vdp_in(n) if n in (0x98,0x99) else 0xFF
            self.tstates += 11
        elif op == 0xC5: self.push(self.bc()); self.tstates += 11; self.tstates_pushpop += 11
        elif op == 0xD5: self.push(self.de()); self.tstates += 11; self.tstates_pushpop += 11
        elif op == 0xE5: self.push(self.hl()); self.tstates += 11; self.tstates_pushpop += 11
        elif op == 0xF5: self.push((self.a<<8)|self.f); self.tstates += 11; self.tstates_pushpop += 11
        elif op == 0xC1: self.setbc(self.pop()); self.tstates += 10; self.tstates_pushpop += 10
        elif op == 0xD1: self.setde(self.pop()); self.tstates += 10; self.tstates_pushpop += 10
        elif op == 0xE1: self.sethl(self.pop()); self.tstates += 10; self.tstates_pushpop += 10
        elif op == 0xF1:
            v=self.pop(); self.a=(v>>8)&0xFF; self.f=v&0xFF
            self.tstates += 10; self.tstates_pushpop += 10
        elif op == 0xD9:  # EXX (not swapping shadow - unused in this code presumably)
            self.tstates += 4
        elif op == 0xDD:
            self.step_dd()
            return
        elif op == 0xFD:
            self.step_fd()
            return
        elif op == 0xED:
            self.step_ed()
            return
        elif op == 0xCB:
            self.step_cb()
            return
        elif 0x40 <= op <= 0x7F and op != 0x76:  # LD r,r'/  LD r,(HL) / LD (HL),r
            dst=(op>>3)&7; src=op&7
            if dst==6:  # LD (HL),r
                self.wr(self.hl(), self.getr8(src)); self.tstates += 7
            elif src==6:  # LD r,(HL)
                self.setr8(dst, self.rd(self.hl())); self.tstates += 7
            else:
                self.setr8(dst, self.getr8(src)); self.tstates += 4
        elif (op & 0xC7) == 0x06:  # LD r,n / LD (HL),n
            dst=(op>>3)&7
            n=self.fetch()
            if dst==6: self.wr(self.hl(), n); self.tstates += 10
            else: self.setr8(dst,n); self.tstates += 7
        elif op in (0x01,0x11,0x21,0x31):  # LD rr,nn
            n=self.fetch16()
            if op==0x01: self.setbc(n)
            elif op==0x11: self.setde(n)
            elif op==0x21: self.sethl(n)
            elif op==0x31: self.sp=n
            self.tstates += 10
        elif op == 0x2A:  # LD HL,(nn)
            addr=self.fetch16()
            self.l=self.rd(addr); self.h=self.rd(addr+1)
            self.tstates += 16
        elif op == 0x22:  # LD (nn),HL
            addr=self.fetch16()
            self.wr(addr,self.l); self.wr(addr+1,self.h)
            self.tstates += 16
        elif op == 0x32:  # LD (nn),A
            addr=self.fetch16(); self.wr(addr,self.a)
            self.tstates += 13
        elif op == 0x3A:  # LD A,(nn)
            addr=self.fetch16(); self.a=self.rd(addr)
            self.tstates += 13
        elif op == 0x02: self.wr(self.bc(), self.a); self.tstates += 7
        elif op == 0x12: self.wr(self.de(), self.a); self.tstates += 7
        elif op == 0x0A: self.a=self.rd(self.bc()); self.tstates += 7
        elif op == 0x1A: self.a=self.rd(self.de()); self.tstates += 7
        elif op == 0xF9: self.sp=self.hl(); self.tstates += 6
        elif op in (0x04,0x0C,0x14,0x1C,0x24,0x2C,0x3C):  # INC r
            r=(op>>3)&7
            v=(self.getr8(r)+1)&0xFF
            self.setr8(r,v); self.setZ(v); self.setS(v)
            self.tstates += 4
        elif op == 0x34:
            v=(self.rd(self.hl())+1)&0xFF; self.wr(self.hl(),v); self.setZ(v); self.setS(v)
            self.tstates += 11
        elif op in (0x05,0x0D,0x15,0x1D,0x25,0x2D,0x3D):
            r=(op>>3)&7
            v=(self.getr8(r)-1)&0xFF
            self.setr8(r,v); self.setZ(v); self.setS(v)
            self.tstates += 4
        elif op == 0x35:
            v=(self.rd(self.hl())-1)&0xFF; self.wr(self.hl(),v); self.setZ(v); self.setS(v)
            self.tstates += 11
        elif op in (0x03,0x13,0x23,0x33):  # INC rr
            if op==0x03: self.setbc((self.bc()+1)&0xFFFF)
            elif op==0x13: self.setde((self.de()+1)&0xFFFF)
            elif op==0x23: self.sethl((self.hl()+1)&0xFFFF)
            elif op==0x33: self.sp=(self.sp+1)&0xFFFF
            self.tstates += 6
        elif op in (0x0B,0x1B,0x2B,0x3B):
            if op==0x0B: self.setbc((self.bc()-1)&0xFFFF)
            elif op==0x1B: self.setde((self.de()-1)&0xFFFF)
            elif op==0x2B: self.sethl((self.hl()-1)&0xFFFF)
            elif op==0x3B: self.sp=(self.sp-1)&0xFFFF
            self.tstates += 6
        elif op in (0x09,0x19,0x29,0x39):  # ADD HL,rr
            src = {0x09:self.bc(),0x19:self.de(),0x29:self.hl(),0x39:self.sp}[op]
            res = self.hl()+src
            if res>0xFFFF: self.f|=0x01
            else: self.f&=~0x01
            self.sethl(res&0xFFFF)
            self.tstates += 11
        elif 0x80<=op<=0x87:  # ADD A,r/(HL)
            r=op&7
            v = self.rd(self.hl()) if r==6 else self.getr8(r)
            res=self.a+v
            self.f = (0x01 if res>0xFF else 0)
            self.a = res&0xFF; self.setZ(self.a); self.setS(self.a)
            self.tstates += 7 if r==6 else 4
        elif op == 0xC6:  # ADD A,n
            n=self.fetch(); res=self.a+n
            self.f = (0x01 if res>0xFF else 0)
            self.a=res&0xFF; self.setZ(self.a); self.setS(self.a)
            self.tstates += 7
        elif 0x90<=op<=0x97:  # SUB r
            r=op&7
            v = self.rd(self.hl()) if r==6 else self.getr8(r)
            res=self.a-v
            self.f=(0x01 if res<0 else 0)|0x02
            self.a=res&0xFF; self.setZ(self.a); self.setS(self.a)
            self.tstates += 7 if r==6 else 4
        elif op == 0xD6:
            n=self.fetch(); res=self.a-n
            self.f=(0x01 if res<0 else 0)|0x02
            self.a=res&0xFF; self.setZ(self.a); self.setS(self.a)
            self.tstates += 7
        elif 0xA0<=op<=0xA7:  # AND r
            r=op&7
            v = self.rd(self.hl()) if r==6 else self.getr8(r)
            self.a &= v; self.f=0x10; self.setZ(self.a); self.setS(self.a)
            self.tstates += 7 if r==6 else 4
        elif op == 0xE6:
            n=self.fetch(); self.a &= n; self.f=0x10; self.setZ(self.a); self.setS(self.a)
            self.tstates += 7
        elif 0xA8<=op<=0xAF:  # XOR r
            r=op&7
            v = self.rd(self.hl()) if r==6 else self.getr8(r)
            self.a ^= v; self.f=0; self.setZ(self.a); self.setS(self.a)
            self.tstates += 7 if r==6 else 4
        elif op == 0xEE:
            n=self.fetch(); self.a ^= n; self.f=0; self.setZ(self.a); self.setS(self.a)
            self.tstates += 7
        elif 0xB0<=op<=0xB7:  # OR r
            r=op&7
            v = self.rd(self.hl()) if r==6 else self.getr8(r)
            self.a |= v; self.f=0; self.setZ(self.a); self.setS(self.a)
            self.tstates += 7 if r==6 else 4
        elif op == 0xF6:
            n=self.fetch(); self.a |= n; self.f=0; self.setZ(self.a); self.setS(self.a)
            self.tstates += 7
        elif 0xB8<=op<=0xBF:  # CP r
            r=op&7
            v = self.rd(self.hl()) if r==6 else self.getr8(r)
            res=self.a-v
            self.f=(0x01 if res<0 else 0)|0x02
            self.setZ(res&0xFF); self.setS(res&0xFF)
            self.tstates += 7 if r==6 else 4
        elif op == 0xFE:
            n=self.fetch(); res=self.a-n
            self.f=(0x01 if res<0 else 0)|0x02
            self.setZ(res&0xFF); self.setS(res&0xFF)
            self.tstates += 7
        elif op == 0x98:  # SBC A,B (also handles A,r via 0x98+r)
            self.tstates += 4
        elif 0x98<=op<=0x9F:  # SBC A,r
            r=op&7
            v = self.rd(self.hl()) if r==6 else self.getr8(r)
            carry = self.f&0x01
            res=self.a-v-carry
            self.f=(0x01 if res<0 else 0)|0x02
            self.a=res&0xFF; self.setZ(self.a); self.setS(self.a)
            self.tstates += 7 if r==6 else 4
        elif op == 0xDE:
            n=self.fetch(); carry=self.f&0x01
            res=self.a-n-carry
            self.f=(0x01 if res<0 else 0)|0x02
            self.a=res&0xFF; self.setZ(self.a); self.setS(self.a)
            self.tstates += 7
        else:
            raise Exception(f"unhandled opcode {op:02X} at {pc0:04X}")

    def check_cc(self,cc):
        return {
            0: not(self.f&0x40), 1: bool(self.f&0x40),
            2: not(self.f&0x01), 3: bool(self.f&0x01),
            4: not(self.f&0x04), 5: bool(self.f&0x04),
            6: not(self.f&0x80), 7: bool(self.f&0x80),
        }.get(cc,False)

    def step_dd(self):
        # All DD-prefixed (IX) instruction timings below already include
        # the DD-prefix fetch, matching the documented total instruction
        # time (e.g. LD r,(IX+d) = 19 T-states total, not 4+15).
        self.instr_count_indexed += 1
        op=self.fetch()
        if op == 0x21:  # LD IX,nn
            self.ix=self.fetch16()
            cost = 14
        elif op == 0x2A:
            addr=self.fetch16()
            self.ix = self.rd(addr) | (self.rd(addr+1)<<8)
            cost = 20
        elif op == 0x23: self.ix=(self.ix+1)&0xFFFF; cost = 10
        elif op == 0x2B: self.ix=(self.ix-1)&0xFFFF; cost = 10
        elif op == 0xE5: self.push(self.ix); cost = 15; self.tstates_pushpop += 15
        elif op == 0xE1: self.ix=self.pop(); cost = 14; self.tstates_pushpop += 14
        elif (op&0xC7)==0x46:  # LD r,(IX+d)
            dst=(op>>3)&7
            d=self.fetch()
            if d>127: d-=256
            self.setr8(dst, self.rd(self.ix+d))
            cost = 19
        elif (op&0xF8)==0x70 and op!=0x76:  # LD (IX+d),r
            src=op&7
            d=self.fetch()
            if d>127: d-=256
            self.wr(self.ix+d, self.getr8(src))
            cost = 19
        elif op == 0x36:  # LD (IX+d),n
            d=self.fetch()
            if d>127: d-=256
            n=self.fetch()
            self.wr(self.ix+d, n)
            cost = 19
        else:
            raise Exception(f"unhandled DD op {op:02X} at {self.pc-2:04X}")
        self.tstates += cost
        self.tstates_indexed += cost

    def step_fd(self):
        self.instr_count_indexed += 1
        op=self.fetch()
        if op == 0xE5: self.push(self.iy); cost = 15; self.tstates_pushpop += 15
        elif op == 0xE1: self.iy=self.pop(); cost = 14; self.tstates_pushpop += 14
        elif op == 0x21: self.iy=self.fetch16(); cost = 14
        else:
            raise Exception(f"unhandled FD op {op:02X} at {self.pc-2:04X}")
        self.tstates += cost
        self.tstates_indexed += cost

    def step_ed(self):
        op=self.fetch()
        if op == 0xB0:  # LDIR
            reps=0
            while True:
                v=self.rd(self.hl()); self.wr(self.de(),v)
                self.sethl((self.hl()+1)&0xFFFF); self.setde((self.de()+1)&0xFFFF)
                self.setbc((self.bc()-1)&0xFFFF)
                reps+=1
                if self.bc()==0: break
            self.tstates += 21*(reps-1)+16
        elif op == 0xB8:  # LDDR
            reps=0
            while True:
                v=self.rd(self.hl()); self.wr(self.de(),v)
                self.sethl((self.hl()-1)&0xFFFF); self.setde((self.de()-1)&0xFFFF)
                self.setbc((self.bc()-1)&0xFFFF)
                reps+=1
                if self.bc()==0: break
            self.tstates += 21*(reps-1)+16
        elif op == 0xB3:  # OTIR
            reps=0
            while True:
                v=self.rd(self.hl())
                port=self.c
                if port in (0x98,0x99): self.vdp_out(port,v)
                self.sethl((self.hl()+1)&0xFFFF)
                self.b=(self.b-1)&0xFF
                reps+=1
                if self.b==0: break
            self.tstates += 21*(reps-1)+16
        elif op in (0x4B,0x5B,0x7B):  # LD rr,(nn)
            addr=self.fetch16()
            lo=self.rd(addr); hi=self.rd(addr+1)
            if op==0x4B: self.setbc(lo|(hi<<8))
            elif op==0x5B: self.setde(lo|(hi<<8))
            elif op==0x7B: self.sp=lo|(hi<<8)
            self.tstates += 20
        elif op in (0x43,0x53,0x73):
            addr=self.fetch16()
            v = self.bc() if op==0x43 else self.de() if op==0x53 else self.sp
            self.wr(addr,v&0xFF); self.wr(addr+1,(v>>8)&0xFF)
            self.tstates += 20
        elif (op&0xCF)==0x42:  # SBC HL,rr
            rr=(op>>4)&3
            src={0:self.bc(),1:self.de(),2:self.hl(),3:self.sp}[rr]
            carry=self.f&0x01
            res=self.hl()-src-carry
            self.f=(0x01 if res<0 else 0)|0x02
            self.sethl(res&0xFFFF)
            self.tstates += 15
        else:
            raise Exception(f"unhandled ED op {op:02X} at {self.pc-2:04X}")

    def step_cb(self):
        op=self.fetch()
        if (op&0xF8)==0x38:  # SRL r
            r=op&7
            v = self.rd(self.hl()) if r==6 else self.getr8(r)
            carry = v&1
            v = v>>1
            if r==6: self.wr(self.hl(),v)
            else: self.setr8(r,v)
            self.f = carry
            self.setZ(v); self.setS(v)
            self.tstates += 15 if r==6 else 8
        else:
            raise Exception(f"unhandled CB op {op:02X} at {self.pc-2:04X}")

    def run_until_halt(self, max_instr=2000000):
        for _ in range(max_instr):
            if self.halted:
                return True
            self.step()
        return False
