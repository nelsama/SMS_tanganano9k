#!/usr/bin/env python3
"""z80asm.py in.s out.bin [size] : small two-pass Z80 assembler.
Labels 'name:', constants 'name = expr', .org .db .dw .ds .incbin.
Expressions are Python ones; $ is the current address, $hex / 0x / 'c' work.
Unused space is filled with FF up to size."""
import re, sys, os
R8 = {'b': 0, 'c': 1, 'd': 2, 'e': 3, 'h': 4, 'l': 5, '(hl)': 6, 'a': 7}
R16 = {'bc': 0, 'de': 1, 'hl': 2, 'sp': 3}
R16P = {'bc': 0, 'de': 1, 'hl': 2, 'af': 3}
CC = {'nz': 0, 'z': 1, 'nc': 2, 'c': 3, 'po': 4, 'pe': 5, 'p': 6, 'm': 7}
ALU = {'add': 0, 'adc': 1, 'sub': 2, 'sbc': 3, 'and': 4, 'xor': 5, 'or': 6, 'cp': 7}
ROT = {'rlc': 0, 'rrc': 1, 'rl': 2, 'rr': 3, 'sla': 4, 'sra': 5, 'sll': 6, 'srl': 7}
SIMPLE = dict(nop=[0], halt=[0x76], di=[0xF3], ei=[0xFB], ret=[0xC9], exx=[0xD9], rlca=[7], rrca=[15],
  rla=[0x17], rra=[0x1F], daa=[0x27], cpl=[0x2F], scf=[0x37], ccf=[0x3F], neg=[0xED, 0x44], reti=[0xED, 0x4D],
  retn=[0xED, 0x45], rrd=[0xED, 0x67], rld=[0xED, 0x6F], ldi=[0xED, 0xA0], cpi=[0xED, 0xA1], ini=[0xED, 0xA2],
  outi=[0xED, 0xA3], ldd=[0xED, 0xA8], cpd=[0xED, 0xA9], ind=[0xED, 0xAA], outd=[0xED, 0xAB], ldir=[0xED, 0xB0],
  cpir=[0xED, 0xB1], inir=[0xED, 0xB2], otir=[0xED, 0xB3], lddr=[0xED, 0xB8], cpdr=[0xED, 0xB9])
src, out = sys.argv[1:3]
size = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0
sym, mem, pc, final = {}, {}, 0, False

def split(s):
    res, cur, d, q = [], '', 0, None
    for ch in s:
        if q: cur += ch; q = None if ch == q else q; continue
        if ch in '"\'': q = ch
        if ch == '(': d += 1
        if ch == ')': d -= 1
        if ch == ',' and d == 0: res.append(cur.strip()); cur = ''
        else: cur += ch
    if cur.strip(): res.append(cur.strip())
    return res
def ev(e):
    e = re.sub(r"'(.)'", lambda m: str(ord(m.group(1))), e)
    e = re.sub(r'\$([0-9a-fA-F]+)', r'0x\1', e).replace('$', str(pc))
    try: return int(eval(e, {'__builtins__': {}}, sym))
    except NameError:
        if final: raise
        return 0
def lo(e): return ev(e) & 255
def w(e): v = ev(e); return [v & 255, v >> 8 & 255]
def rel(e):
    d = ev(e) - (pc + 2)
    if final and not -128 <= d <= 127: raise ValueError('jr range')
    return d & 255
def mem_(x): return x.startswith('(') and x.endswith(')')

def enc(op, a):
    l = [x.lower() for x in a]
    # IX / IY: rewrite as HL with a prefix
    for pre, r in ((0xDD, 'ix'), (0xFD, 'iy')):
        for i, x in enumerate(l):
            m = re.match(r'\(' + r + r'\s*([+-].*)?\)$', x)
            if m and not (op == 'jp'):
                k = list(a); k[i] = '(hl)'
                c = enc(op, k); d = lo(m.group(1) or '0')
                return [pre, 0xCB, d, c[1]] if c[0] == 0xCB else [pre, c[0], d] + c[1:]
            if x == r or x == '(' + r + ')':
                return [pre] + enc(op, [y.replace(r, 'hl') for y in l])
    if op in SIMPLE and not a: return SIMPLE[op]
    if op == 'ld':
        d, s = l
        if d in R8 and s in R8 and not (d == s == '(hl)'): return [0x40 | R8[d] << 3 | R8[s]]
        if d == 'a' and s in ('(bc)', '(de)'): return [0x0A if s == '(bc)' else 0x1A]
        if s == 'a' and d in ('(bc)', '(de)'): return [0x02 if d == '(bc)' else 0x12]
        if d == 'a' and s in 'ir': return [0xED, 0x57 if s == 'i' else 0x5F]
        if s == 'a' and d in 'ir': return [0xED, 0x47 if d == 'i' else 0x4F]
        if d == 'sp' and s == 'hl': return [0xF9]
        if d == 'a' and mem_(s): return [0x3A] + w(a[1])
        if mem_(d) and s == 'a': return [0x32] + w(a[0])
        if d == 'hl' and mem_(s): return [0x2A] + w(a[1])
        if mem_(d) and s == 'hl': return [0x22] + w(a[0])
        if d in R16 and mem_(s): return [0xED, 0x4B | R16[d] << 4] + w(a[1])
        if mem_(d) and s in R16: return [0xED, 0x43 | R16[s] << 4] + w(a[0])
        if d in R16: return [0x01 | R16[d] << 4] + w(a[1])
        if d in R8: return [0x06 | R8[d] << 3, lo(a[1])]
    if op in ('inc', 'dec'):
        k = op == 'dec'
        if l[0] in R16: return [(0x0B if k else 0x03) | R16[l[0]] << 4]
        return [(5 if k else 4) | R8[l[0]] << 3]
    if op in ALU:
        if l[0] == 'hl':
            if op == 'add': return [0x09 | R16[l[1]] << 4]
            return [0xED, (0x4A if op == 'adc' else 0x42) | R16[l[1]] << 4]
        x = l[-1]
        return [0x80 | ALU[op] << 3 | R8[x]] if x in R8 else [0xC6 | ALU[op] << 3, lo(a[-1])]
    if op in ROT: return [0xCB, ROT[op] << 3 | R8[l[0]]]
    if op in ('bit', 'res', 'set'): return [0xCB, {'bit': 0x40, 'res': 0x80, 'set': 0xC0}[op] | ev(a[0]) << 3 | R8[l[1]]]
    if op == 'push': return [0xC5 | R16P[l[0]] << 4]
    if op == 'pop': return [0xC1 | R16P[l[0]] << 4]
    if op == 'jp':
        if l[0] in ('(hl)', 'hl'): return [0xE9]
        return [0xC2 | CC[l[0]] << 3] + w(a[1]) if len(a) == 2 else [0xC3] + w(a[0])
    if op == 'call': return [0xC4 | CC[l[0]] << 3] + w(a[1]) if len(a) == 2 else [0xCD] + w(a[0])
    if op == 'jr': return [0x20 | CC[l[0]] << 3, rel(a[1])] if len(a) == 2 else [0x18, rel(a[0])]
    if op == 'djnz': return [0x10, rel(a[0])]
    if op == 'ret': return [0xC0 | CC[l[0]] << 3]
    if op == 'rst': return [0xC7 | ev(a[0])]
    if op == 'im': return [0xED, (0x46, 0x56, 0x5E)[ev(a[0])]]
    if op == 'in': return [0xED, 0x40 | R8[l[0]] << 3] if l[1] == '(c)' else [0xDB, lo(a[1])]
    if op == 'out': return [0xED, 0x41 | R8[l[1]] << 3] if l[0] == '(c)' else [0xD3, lo(a[0])]
    if op == 'ex': return [{'de': 0xEB, 'af': 0x08, '(sp)': 0xE3}[l[0]]]
    raise ValueError('bad instruction')

lines = open(src).read().split('\n')
for final in (False, True):
    pc = 0
    for n, line in enumerate(lines, 1):
        s = re.sub(r';.*', '', line) if '"' not in line else re.sub(r';[^"]*$', '', line)
        s = s.strip()
        try:
            m = re.match(r'(\w+):\s*', s)
            if m: sym[m.group(1)] = pc; s = s[m.end():]
            if not s: continue
            m = re.match(r'(\w+)\s*=\s*(.+)$', s)
            if m: sym[m.group(1)] = ev(m.group(2)); continue
            op, _, rest = s.partition(' '); op = op.lower(); a = split(rest)
            if op == '.org': pc = ev(a[0]); continue
            if op == '.ds': pc += ev(a[0]); continue
            if op == '.db':
                c = []
                for x in a: c += [ord(q) for q in x[1:-1]] if x[0] == '"' else [lo(x)]
            elif op == '.dw': c = sum((w(x) for x in a), [])
            elif op == '.incbin': c = list(open(os.path.join(os.path.dirname(src), a[0].strip('"')), 'rb').read())
            else: c = enc(op, a)
            for x in c:
                if final and pc in mem: raise ValueError('overlap at %04x' % pc)
                if final: mem[pc] = x
                pc += 1
        except Exception as e: sys.exit('%s:%d: %s: %s' % (src, n, line.strip(), e))
end = max(mem) + 1
size = size or end
if end > size: sys.exit('too big: %d > %d' % (end, size))
open(out, 'wb').write(bytes(mem.get(i, 255) for i in range(size)))
print('%s: %d bytes used' % (out, len(mem)))
