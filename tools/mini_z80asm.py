#!/usr/bin/env python3
"""
Minimal two-pass Z80 assembler for the CYBER_G_SCREEN1 sjasmplus-style source.
Supports exactly the syntax subset used in that file:
  ORG, EQU, DB, DW, DS, ALIGN
  LD (8/16-bit, incl. (HL)/(BC)/(DE)/(IX+d)/(nn) forms used), INC/DEC (r, rr, IX)
  ADD A,r/n ; ADD HL,rr ; SUB/AND/XOR/OR/CP r or n
  SRL r (CB-prefixed)
  JR/JP (unconditional + NZ/Z/NC/C) , CALL (unconditional), RET (unconditional)
  DJNZ, DI, EI, OUT (n),A, IN A,(n), LDIR, OTIR
  ':'-separated multiple statements per line, ';' comments, hex 'NNNNh' literals,
  simple label(+/-N) and label/256 expressions.
"""
import sys, re

REG8 = {"B":0,"C":1,"D":2,"E":3,"H":4,"L":5,"A":7}
REG16 = {"BC":0,"DE":1,"HL":2,"SP":3}
COND = {"NZ":0,"Z":1,"NC":2,"C":3,"PO":4,"PE":5,"P":6,"M":7}

class AsmError(Exception):
    pass

def split_top_commas(s):
    parts = []
    depth = 0
    cur = ""
    for ch in s:
        if ch == '(':
            depth += 1
            cur += ch
        elif ch == ')':
            depth -= 1
            cur += ch
        elif ch == ',' and depth == 0:
            parts.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip() != "" or parts:
        parts.append(cur.strip())
    return parts

def split_statements(line):
    # split on ':' but ':' never appears inside our expressions/strings in this source
    return [s.strip() for s in line.split(':')]

class Assembler:
    def __init__(self, text):
        self.lines = text.split('\n')
        self.symtab = {}   # name -> int value
        self.pc = 0
        self.output = {}   # address -> byte value (sparse), we will also track min/max
        self.string_re = re.compile(r'^"(.*)"$')

    # ---------- expression evaluation ----------
    def eval_expr(self, s, phase):
        s = s.strip()
        if s == "":
            raise AsmError("empty expression")
        # split on top-level + or - or / or * (left to right, simple, no operator precedence needed
        # for this source: expressions are like NAME, NAME+N, NAME-N, NAME/256, plain hex/dec numbers)
        # tokenize
        m = re.match(r'^([^+\-*/]+)([+\-*/].*)?$', s)
        if not m:
            return self.eval_atom(s, phase)
        first = m.group(1).strip()
        rest = m.group(2)
        val = self.eval_atom(first, phase)
        while rest:
            op = rest[0]
            m2 = re.match(r'^([+\-*/]?[^+\-*/]+)(.*)$', rest[1:])
            if not m2:
                break
            term = m2.group(1).strip()
            rest = m2.group(2)
            tval = self.eval_atom(term, phase)
            if op == '+':
                val += tval
            elif op == '-':
                val -= tval
            elif op == '*':
                val *= tval
            elif op == '/':
                val = val // tval
        return val & 0xFFFFFFFF if val >= 0 else val

    def eval_atom(self, tok, phase):
        tok = tok.strip()
        if tok == "":
            raise AsmError("empty atom")
        if tok.startswith('-'):
            return -self.eval_atom(tok[1:], phase)
        # hex literal NNNNh (also accepts forms like 'A0h' without a leading 0,
        # as used in this source; requires at least one hex digit before the h)
        if re.match(r'^[0-9A-Fa-f]+[hH]$', tok) and len(tok) > 1:
            return int(tok[:-1], 16)
        # plain decimal
        if re.match(r'^[0-9]+$', tok):
            return int(tok)
        # $ / current pc (not used but harmless)
        if tok == '$':
            return self.pc
        # symbol
        name = tok.upper()
        if name in self.symtab:
            return self.symtab[name]
        if phase == 1:
            return 0  # placeholder; not resolved until pass 2, value unused for length calc
        raise AsmError(f"undefined symbol '{tok}'")

    def set_sym(self, name, value):
        self.symtab[name.upper()] = value & 0xFFFFFFFF

    # ---------- byte emission ----------
    def emit(self, byte_list):
        for b in byte_list:
            self.output[self.pc] = b & 0xFF
            self.pc += 1

    # ---------- operand classification ----------
    def classify_mem(self, inner, phase):
        inner = inner.strip()
        iu = inner.upper()
        if iu == "HL":
            return ("mHL", None)
        if iu == "BC":
            return ("mBC", None)
        if iu == "DE":
            return ("mDE", None)
        m = re.match(r'^IX\s*([+\-]\s*.+)$', iu)
        if m:
            d = self.eval_expr(inner[len(m.group(0)) - len(m.group(1)):].strip(), phase) if False else None
        m2 = re.match(r'^IX\s*\+\s*(.+)$', iu, re.IGNORECASE)
        if m2:
            dexpr = inner[re.match(r'^IX\s*\+', inner, re.IGNORECASE).end():].strip()
            return ("mIXd", self.eval_expr(dexpr, phase))
        m3 = re.match(r'^IX\s*-\s*(.+)$', iu, re.IGNORECASE)
        if m3:
            dexpr = inner[re.match(r'^IX\s*-', inner, re.IGNORECASE).end():].strip()
            return ("mIXd", -self.eval_expr(dexpr, phase))
        m4 = re.match(r'^IY\s*\+\s*(.+)$', iu, re.IGNORECASE)
        if m4:
            dexpr = inner[re.match(r'^IY\s*\+', inner, re.IGNORECASE).end():].strip()
            return ("mIYd", self.eval_expr(dexpr, phase))
        m5 = re.match(r'^IY\s*-\s*(.+)$', iu, re.IGNORECASE)
        if m5:
            dexpr = inner[re.match(r'^IY\s*-', inner, re.IGNORECASE).end():].strip()
            return ("mIYd", -self.eval_expr(dexpr, phase))
        # else absolute address / port number expression
        return ("mNN", self.eval_expr(inner, phase))

    def classify_operand(self, op, phase):
        op = op.strip()
        if op.startswith('(') and op.endswith(')'):
            return self.classify_mem(op[1:-1], phase)
        u = op.upper()
        if u in REG8:
            return ("r8", REG8[u])
        if u in REG16:
            return ("r16", REG16[u])
        if u == "IX":
            return ("ix", None)
        if u == "IY":
            return ("iy", None)
        if u == "AF":
            return ("af", None)
        # condition codes are handled separately by caller context
        return ("imm", op)  # expression string, resolved lazily

    # ---------- instruction encoders ----------
    def asm_instr(self, mnem, rest, phase):
        mnem = mnem.upper()
        pc0 = self.pc

        if mnem == "LD":
            ops = split_top_commas(rest)
            if len(ops) != 2:
                raise AsmError(f"LD needs 2 operands: {rest}")
            dst = self.classify_operand(ops[0], phase)
            src = self.classify_operand(ops[1], phase)
            self.enc_ld(dst, src, phase)
            return

        if mnem in ("INC", "DEC"):
            op = self.classify_operand(rest, phase)
            base_r = 0x04 if mnem == "INC" else 0x05
            base_rr = {"BC":0x03,"DE":0x13,"HL":0x23,"SP":0x33} if mnem=="INC" else {"BC":0x0B,"DE":0x1B,"HL":0x2B,"SP":0x3B}
            if op[0] == "r8":
                self.emit([base_r + op[1]*8])
            elif op[0] == "mHL":
                self.emit([0x34 if mnem=="INC" else 0x35])
            elif op[0] == "r16":
                name = rest.strip().upper()
                self.emit([base_rr[name]])
            elif op[0] == "ix":
                self.emit([0xDD, 0x23 if mnem=="INC" else 0x2B])
            elif op[0] == "iy":
                self.emit([0xFD, 0x23 if mnem=="INC" else 0x2B])
            else:
                raise AsmError(f"bad {mnem} operand: {rest}")
            return

        if mnem in ("ADD","SUB","AND","XOR","OR","CP"):
            ops = split_top_commas(rest)
            if mnem == "ADD" and len(ops) == 2:
                dst = self.classify_operand(ops[0], phase)
                src = self.classify_operand(ops[1], phase)
                if dst[0] == "r16" and ops[0].strip().upper()=="HL":
                    rr = {"BC":0x00,"DE":0x10,"HL":0x20,"SP":0x30}[ops[1].strip().upper()]
                    self.emit([0x09 + rr])
                    return
                # ADD A,x
                self.enc_alu_a(0x80, src, phase)  # ADD A,r base 0x80 ; imm handled inside (0xC6)
                return
            else:
                # single-operand form implies A as left side: SUB/AND/XOR/OR/CP r|n  and ADD with 1 operand not used
                srcop = ops[-1]
                src = self.classify_operand(srcop, phase)
                bases = {"SUB":(0x90,0xD6), "AND":(0xA0,0xE6), "XOR":(0xA8,0xEE), "OR":(0xB0,0xF6), "CP":(0xB8,0xFE)}
                rbase, ibase = bases[mnem]
                self.enc_alu_a(rbase, src, phase, immop=ibase)
                return

        if mnem == "SRL":
            op = self.classify_operand(rest, phase)
            if op[0] == "r8":
                self.emit([0xCB, 0x38 + op[1]])
            elif op[0] == "mHL":
                self.emit([0xCB, 0x3E])
            else:
                raise AsmError(f"bad SRL operand: {rest}")
            return

        if mnem == "JR":
            self.enc_jr_djnz(rest, phase, is_djnz=False)
            return
        if mnem == "DJNZ":
            self.enc_jr_djnz(rest, phase, is_djnz=True)
            return

        if mnem == "JP":
            ops = split_top_commas(rest)
            if len(ops) == 2:
                cc = ops[0].strip().upper()
                target = self.eval_expr(ops[1], phase)
                opc = {"NZ":0xC2,"Z":0xCA,"NC":0xD2,"C":0xDA,"PO":0xE2,"PE":0xEA,"P":0xF2,"M":0xFA}[cc]
                self.emit([opc, target & 0xFF, (target >> 8) & 0xFF])
            else:
                target = self.eval_expr(ops[0], phase)
                self.emit([0xC3, target & 0xFF, (target >> 8) & 0xFF])
            return

        if mnem == "CALL":
            ops = split_top_commas(rest)
            if len(ops) == 2:
                cc = ops[0].strip().upper()
                target = self.eval_expr(ops[1], phase)
                opc = {"NZ":0xC4,"Z":0xCC,"NC":0xD4,"C":0xDC,"PO":0xE4,"PE":0xEC,"P":0xF4,"M":0xFC}[cc]
                self.emit([opc, target & 0xFF, (target >> 8) & 0xFF])
            else:
                target = self.eval_expr(ops[0], phase)
                self.emit([0xCD, target & 0xFF, (target >> 8) & 0xFF])
            return

        if mnem == "RET":
            if rest.strip() == "":
                self.emit([0xC9])
            else:
                cc = rest.strip().upper()
                opc = {"NZ":0xC0,"Z":0xC8,"NC":0xD0,"C":0xD8,"PO":0xE0,"PE":0xE8,"P":0xF0,"M":0xF8}[cc]
                self.emit([opc])
            return

        if mnem == "DI":
            self.emit([0xF3]); return
        if mnem == "EI":
            self.emit([0xFB]); return
        if mnem == "NOP":
            self.emit([0x00]); return
        if mnem == "HALT":
            self.emit([0x76]); return

        if mnem == "OUT":
            ops = split_top_commas(rest)
            memop = ops[0].strip()
            if not (memop.startswith('(') and memop.endswith(')')):
                raise AsmError(f"bad OUT operand: {rest}")
            n = self.eval_expr(memop[1:-1], phase)
            self.emit([0xD3, n & 0xFF])
            return

        if mnem == "IN":
            ops = split_top_commas(rest)
            memop = ops[1].strip()
            n = self.eval_expr(memop[1:-1], phase)
            self.emit([0xDB, n & 0xFF])
            return

        if mnem == "PUSH":
            name = rest.strip().upper()
            push_op = {"BC":0xC5, "DE":0xD5, "HL":0xE5, "AF":0xF5}
            if name == "IX":
                self.emit([0xDD, 0xE5]); return
            if name == "IY":
                self.emit([0xFD, 0xE5]); return
            if name in push_op:
                self.emit([push_op[name]]); return
            raise AsmError(f"unsupported PUSH operand '{rest}'")

        if mnem == "POP":
            name = rest.strip().upper()
            pop_op = {"BC":0xC1, "DE":0xD1, "HL":0xE1, "AF":0xF1}
            if name == "IX":
                self.emit([0xDD, 0xE1]); return
            if name == "IY":
                self.emit([0xFD, 0xE1]); return
            if name in pop_op:
                self.emit([pop_op[name]]); return
            raise AsmError(f"unsupported POP operand '{rest}'")

        if mnem == "SBC":
            ops = split_top_commas(rest)
            dst = ops[0].strip().upper()
            src = ops[1].strip().upper()
            if dst == "HL" and src in REG16:
                self.emit([0xED, 0x42 + REG16[src]*0x10]); return
            if dst == "A":
                # SBC A,r / SBC A,n handled like SUB-style 8-bit ops
                if src in REG8:
                    self.emit([0x98 + REG8[src]]); return
                if src == "(HL)":
                    self.emit([0x9E]); return
                n = self.eval_expr(src, phase)
                self.emit([0xDE, n & 0xFF]); return
            raise AsmError(f"unsupported SBC operands '{rest}'")

        if mnem == "LDIR":
            self.emit([0xED, 0xB0]); return
        if mnem == "LDDR":
            self.emit([0xED, 0xB8]); return
        if mnem == "OTIR":
            self.emit([0xED, 0xB3]); return
        if mnem == "OUTI":
            self.emit([0xED, 0xA3]); return
        if mnem == "OTDR":
            self.emit([0xED, 0xBB]); return
        if mnem == "CPIR":
            self.emit([0xED, 0xB1]); return
        if mnem == "EXX":
            self.emit([0xD9]); return

        raise AsmError(f"unsupported mnemonic '{mnem}' (operands: {rest})")

    def enc_alu_a(self, rbase, src, phase, immop=None):
        if src[0] == "r8":
            self.emit([rbase + src[1]])
        elif src[0] == "mHL":
            self.emit([rbase + 6])
        elif src[0] == "imm":
            if immop is None:
                immop = {0x80:0xC6}[rbase]
            n = self.eval_expr(src[1], phase)
            self.emit([immop, n & 0xFF])
        else:
            raise AsmError(f"bad ALU operand type {src}")

    def enc_jr_djnz(self, rest, phase, is_djnz):
        ops = split_top_commas(rest)
        if is_djnz:
            target_expr = ops[0]
            cc = None
        else:
            if len(ops) == 2:
                cc = ops[0].strip().upper()
                target_expr = ops[1]
            else:
                cc = None
                target_expr = ops[0]
        target = self.eval_expr(target_expr, phase)
        if phase == 2:
            offset = target - (self.pc + 2)
            if offset < -128 or offset > 127:
                raise AsmError(f"JR/DJNZ out of range to {target_expr}: offset {offset}")
            off_byte = offset & 0xFF
        else:
            off_byte = 0
        if is_djnz:
            self.emit([0x10, off_byte])
        elif cc is None:
            self.emit([0x18, off_byte])
        else:
            opc = {"NZ":0x20,"Z":0x28,"NC":0x30,"C":0x38}[cc]
            self.emit([opc, off_byte])

    def enc_ld(self, dst, src, phase):
        # 16-bit destinations
        if dst[0] == "r16":
            rr_name = None
            for k,v in REG16.items():
                if v == dst[1]:
                    rr_name = k
            if src[0] == "mNN":
                if rr_name == "HL":
                    self.emit([0x2A, src[1] & 0xFF, (src[1] >> 8) & 0xFF])
                    return
                else:
                    edop = {"BC":0x4B,"DE":0x5B,"SP":0x7B}[rr_name]
                    self.emit([0xED, edop, src[1] & 0xFF, (src[1] >> 8) & 0xFF])
                    return
            elif src[0] == "imm":
                n = self.eval_expr(src[1], phase)
                base = {"BC":0x01,"DE":0x11,"HL":0x21,"SP":0x31}[rr_name]
                self.emit([base, n & 0xFF, (n >> 8) & 0xFF])
                return
            elif src[0] == "r16" and rr_name == "SP":
                # LD SP,HL
                self.emit([0xF9]); return
            else:
                raise AsmError(f"bad LD {rr_name},<src> {src}")

        if dst[0] == "ix":
            if src[0] == "imm":
                n = self.eval_expr(src[1], phase)
                self.emit([0xDD, 0x21, n & 0xFF, (n >> 8) & 0xFF])
                return
            if src[0] == "mNN":
                self.emit([0xDD, 0x2A, src[1] & 0xFF, (src[1] >> 8) & 0xFF])
                return
            raise AsmError(f"bad LD IX,<src> {src}")

        if dst[0] == "mIXd":
            d = dst[1]
            if src[0] == "r8":
                self.emit([0xDD, 0x70 + src[1], d & 0xFF])
                return
            if src[0] == "imm":
                n = self.eval_expr(src[1], phase)
                self.emit([0xDD, 0x36, d & 0xFF, n & 0xFF])
                return
            raise AsmError(f"bad LD (IX+d),<src> {src}")

        if dst[0] == "iy":
            if src[0] == "imm":
                n = self.eval_expr(src[1], phase)
                self.emit([0xFD, 0x21, n & 0xFF, (n >> 8) & 0xFF])
                return
            if src[0] == "mNN":
                self.emit([0xFD, 0x2A, src[1] & 0xFF, (src[1] >> 8) & 0xFF])
                return
            raise AsmError(f"bad LD IY,<src> {src}")

        if dst[0] == "mIYd":
            d = dst[1]
            if src[0] == "r8":
                self.emit([0xFD, 0x70 + src[1], d & 0xFF])
                return
            if src[0] == "imm":
                n = self.eval_expr(src[1], phase)
                self.emit([0xFD, 0x36, d & 0xFF, n & 0xFF])
                return
            raise AsmError(f"bad LD (IY+d),<src> {src}")

        if dst[0] == "mHL":
            if src[0] == "r8":
                self.emit([0x70 + src[1]])
                return
            if src[0] == "imm":
                n = self.eval_expr(src[1], phase)
                self.emit([0x36, n & 0xFF])
                return
            raise AsmError(f"bad LD (HL),<src> {src}")

        if dst[0] == "mBC":
            if src[0] == "r8" and src[1] == REG8["A"]:
                self.emit([0x02]); return
            raise AsmError("LD (BC),<src> only supports A")

        if dst[0] == "mDE":
            if src[0] == "r8" and src[1] == REG8["A"]:
                self.emit([0x12]); return
            raise AsmError("LD (DE),<src> only supports A")

        if dst[0] == "mNN":
            addr = dst[1]
            if src[0] == "r8" and src[1] == REG8["A"]:
                self.emit([0x32, addr & 0xFF, (addr >> 8) & 0xFF])
                return
            if src[0] == "r16":
                rr_name = None
                for k,v in REG16.items():
                    if v == src[1]:
                        rr_name = k
                if rr_name == "HL":
                    self.emit([0x22, addr & 0xFF, (addr >> 8) & 0xFF])
                    return
                edop = {"BC":0x43,"DE":0x53,"SP":0x73}[rr_name]
                self.emit([0xED, edop, addr & 0xFF, (addr >> 8) & 0xFF])
                return
            raise AsmError(f"bad LD (nn),<src> {src}")

        if dst[0] == "r8":
            if src[0] == "r8":
                self.emit([0x40 + dst[1]*8 + src[1]])
                return
            if src[0] == "mHL":
                self.emit([0x40 + dst[1]*8 + 6])
                return
            if src[0] == "mIXd":
                self.emit([0xDD, 0x46 + dst[1]*8, src[1] & 0xFF])
                return
            if src[0] == "mIYd":
                self.emit([0xFD, 0x46 + dst[1]*8, src[1] & 0xFF])
                return
            if src[0] == "mBC":
                if dst[1] == REG8["A"]:
                    self.emit([0x0A]); return
                raise AsmError("only LD A,(BC) supported")
            if src[0] == "mDE":
                if dst[1] == REG8["A"]:
                    self.emit([0x1A]); return
                raise AsmError("only LD A,(DE) supported")
            if src[0] == "mNN":
                if dst[1] == REG8["A"]:
                    self.emit([0x3A, src[1] & 0xFF, (src[1] >> 8) & 0xFF])
                    return
                raise AsmError("only LD A,(nn) supported for direct 8-bit mem read")
            if src[0] == "imm":
                n = self.eval_expr(src[1], phase)
                self.emit([0x06 + dst[1]*8, n & 0xFF])
                return
            raise AsmError(f"bad LD r,<src> {src}")

        raise AsmError(f"unhandled LD dst {dst}")

    # ---------- directive handling ----------
    def parse_db_items(self, s, phase):
        items = split_top_commas(s)
        out = []
        for it in items:
            it = it.strip()
            m = self.string_re.match(it)
            if m:
                for ch in m.group(1):
                    out.append(ord(ch))
            else:
                out.append(self.eval_expr(it, phase) & 0xFF)
        return out

    def parse_dw_items(self, s, phase):
        items = split_top_commas(s)
        out = []
        for it in items:
            v = self.eval_expr(it, phase)
            out.append(v & 0xFFFF)
        return out

    def do_directive(self, name, rest, phase):
        name = name.upper()
        if name == "ORG":
            self.pc = self.eval_expr(rest, phase)
            return
        if name == "EQU":
            raise AsmError("EQU handled at label-processing stage")
        if name == "DB":
            for b in self.parse_db_items(rest, phase):
                self.emit([b])
            return
        if name == "DW":
            for w in self.parse_dw_items(rest, phase):
                self.emit([w & 0xFF, (w >> 8) & 0xFF])
            return
        if name == "DS":
            ops = split_top_commas(rest)
            count = self.eval_expr(ops[0], phase)
            fill = self.eval_expr(ops[1], phase) if len(ops) > 1 else 0
            self.emit([fill & 0xFF] * count)
            return
        if name == "ALIGN":
            boundary = self.eval_expr(rest, phase)
            if self.pc % boundary != 0:
                pad = boundary - (self.pc % boundary)
                self.emit([0x00] * pad)
            return
        raise AsmError(f"unknown directive {name}")

    # ---------- top-level line processing ----------
    def process(self, phase):
        self.pc_snapshot = None
        for raw in self.lines:
            line = raw.split(';')[0]
            if line.strip() == "":
                continue
            # whole-line label definition: NAME:
            wl = line.strip()
            mlabel = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*$', wl)
            if mlabel:
                if phase == 1:
                    self.set_sym(mlabel.group(1), self.pc)
                continue
            # whole-line EQU: NAME EQU expr  (must handle before generic statement split,
            # since EQU lines never combine with ':' in this source)
            mequ = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s+EQU\s+(.+)$', wl, re.IGNORECASE)
            if mequ:
                val = self.eval_expr(mequ.group(2), phase)
                self.set_sym(mequ.group(1), val)
                continue
            # otherwise, split into ':'-separated statements
            for stmt in split_statements(line):
                stmt = stmt.strip()
                if stmt == "":
                    continue
                m = re.match(r'^([A-Za-z_][A-Za-z0-9_.]*)\s*(.*)$', stmt)
                if not m:
                    raise AsmError(f"cannot parse statement: {stmt!r}")
                head = m.group(1)
                rest = m.group(2).strip()
                headu = head.upper()
                if headu in ("ORG","DB","DW","DS","ALIGN"):
                    self.do_directive(headu, rest, phase)
                else:
                    self.asm_instr(head, rest, phase)

    def assemble(self):
        self.pc = 0
        self.symtab = {}
        self.process(phase=1)
        self.pc = 0
        self.output = {}
        self.process(phase=2)
        return self.output


def main():
    if len(sys.argv) < 3:
        print("usage: mini_z80asm.py input.asm output.rom [rom_size_bytes] [fill_byte_hex]")
        sys.exit(1)
    infile = sys.argv[1]
    outfile = sys.argv[2]
    rom_size = int(sys.argv[3]) if len(sys.argv) > 3 else 16384
    fill = int(sys.argv[4], 16) if len(sys.argv) > 4 else 0xFF

    text = open(infile, encoding='utf-8').read()
    asm = Assembler(text)
    try:
        out = asm.assemble()
    except AsmError as e:
        print(f"ASSEMBLY ERROR: {e}")
        sys.exit(2)

    if not out:
        print("no output produced")
        sys.exit(2)
    base = min(out.keys())
    top = max(out.keys())
    print(f"assembled range: {base:04X}h - {top:04X}h  ({top-base+1} bytes)")

    rom = bytearray([fill]) * rom_size
    for addr, val in out.items():
        off = addr - base
        if off < 0 or off >= rom_size:
            print(f"WARNING: address {addr:04X}h out of ROM window (base {base:04X}h, size {rom_size})")
            continue
        rom[off] = val

    with open(outfile, 'wb') as f:
        f.write(rom)
    print(f"wrote {outfile}: {len(rom)} bytes")

if __name__ == "__main__":
    main()
