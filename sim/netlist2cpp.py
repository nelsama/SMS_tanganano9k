#!/usr/bin/env python3
"""netlist2cpp.py in.vg top out.h : 2-state cycle simulator (C++) of a
GowinSynthesis netlist with one clock. Every net bit is a byte v[i]; eval()
settles the combinational logic, tick() is the clock edge."""
import re, sys
src, top, outf = sys.argv[1:4]
text = open(src).read()
text = re.sub(r'[\\](\S+) ', lambda m: 'esc_' + re.sub(r'\W', '_', m.group(1)) + ' ', re.sub(r'(?m)^//.*$', '', text))

def split_top(s):
    out, depth, cur = [], 0, ''
    for ch in s:
        if ch in '({[': depth += 1
        if ch in ')}]': depth -= 1
        if ch == ',' and depth == 0: out.append(cur); cur = ''
        else: cur += ch
    if cur.strip(): out.append(cur)
    return [x.strip() for x in out]

class Mod: pass
mods = {}
for m in re.finditer(r'(?ms)^module (\S+)\s*\((.*?)\)\s*;(.*?)^endmodule', text):
    M = Mod(); M.rng = {}; M.dir = {}; M.inst = []; M.par = {}; M.assigns = []
    body = re.sub(r'/\*.*?\*/', '', m.group(3), flags=re.S)
    for stmt in re.sub(r'//.*', '', body).split(';'):
        s = ' '.join(stmt.split())
        if not s: continue
        d = re.match(r'(input|output|inout|wire)\s*(?:\[(\d+):(\d+)\])?\s*(.+)$', s)
        if d:
            for n in d.group(4).split(','):
                n = n.strip()
                M.rng[n] = (int(d.group(2)), int(d.group(3))) if d.group(2) else None
                if d.group(1) != 'wire': M.dir[n] = d.group(1)
            continue
        d = re.match(r'defparam (\S+?)\s*\.(\w+)\s*=\s*(.+)$', s)
        if d:
            M.par.setdefault(d.group(1), {})[d.group(2)] = d.group(3).strip(); continue
        d = re.match(r'assign (.+?)\s*=\s*(.+)$', s)
        if d: M.assigns.append((d.group(1), d.group(2))); continue
        d = re.match(r'(\w+) (\S+)\s*\((.*)\)$', s)
        if not d: raise SystemExit('cannot parse: ' + s[:200])
        pins = {}
        for p in split_top(d.group(3)):
            q = re.match(r'\.(\w+)\s*\((.*)\)$', p)
            if not q: raise SystemExit("pin: " + repr(p) + " in " + s[:300])
            pins[q.group(1)] = q.group(2).strip()
        M.inst.append((d.group(1), d.group(2), pins))
    mods[m.group(1)] = M

parent = []
def new():
    parent.append(len(parent)); return len(parent) - 1
def find(x):
    while parent[x] != x:
        parent[x] = parent[parent[x]]; x = parent[x]
    return x
def union(a, b): parent[find(a)] = find(b)
ZERO, ONE = new(), new()
cells = []      # (type, path, pins -> [bits LSB first], params)
names = {}

def flatten(mod, path, bind):
    M = mods[mod]; nets = {}
    def net(n):
        if n not in nets:
            r = M.rng.get(n, None)
            if r: nets[n] = {i: new() for i in range(min(r), max(r) + 1)}
            else: nets[n] = {0: new()}
        return nets[n]
    def expr(e):
        e = e.strip()
        if e == '': return None
        if e[0] == '{':
            out = []
            for x in reversed(split_top(e[1:-1])): out += expr(x)
            return out
        m = re.match(r"(\d+)'([bh])([0-9a-fA-FxX]+)$", e)
        if m:
            v = int(m.group(3), 2 if m.group(2) == 'b' else 16)
            return [ONE if v >> i & 1 else ZERO for i in range(int(m.group(1)))]
        m = re.match(r'([^\[\s]+)\s*\[(\d+)(?::(\d+))?\]$', e)
        if m:
            n = net(m.group(1)); a = int(m.group(2)); b = int(m.group(3) or a)
            return [n[i] for i in range(min(a, b), max(a, b) + 1)]
        n = net(e); return [n[i] for i in sorted(n)]
    for p, bits in bind.items():
        mine = expr(p)
        if bits is None: continue
        if len(mine) != len(bits): raise SystemExit('width %s.%s' % (path, p))
        for a, b in zip(mine, bits): union(a, b)
    for a, b in M.assigns:
        for x, y in zip(expr(a), expr(b)): union(x, y)
    if path == '':
        for p in M.dir: names[p] = expr(p)
    for t, n, pins in M.inst:
        P = {k: expr(v) for k, v in pins.items()}
        if t in mods: flatten(t, path + n + '/', P)
        else: cells.append((t, path + n, P, M.par.get(n, {})))
flatten(top, '', {})

drv = {}
def num(v, d=0):
    if v is None: return d
    m = re.match(r"\d+'([bh])([0-9a-fA-F]+)$", v)
    return int(m.group(2), 2 if m.group(1) == 'b' else 16) if m else int(v.strip('"'))

comb, seq, nxt, init, mems = [], [], [], [], []
used = set()
def V(b):
    f = find(b)
    if f in const: return const[f]
    used.add(f); return 'v[%d]' % f
const = {}
for t, n, P, _ in cells:
    if t == 'GND': const[find(P['G'][0])] = '0'
    if t == 'VCC': const[find(P['V'][0])] = '1'
const[find(ZERO)] = '0'; const[find(ONE)] = '1'

def deps(bits): return [find(b) for b in bits if find(b) not in const]
def addc(outs, ins, code): comb.append(([find(o) for o in outs], deps(ins), code))
def num_expr(bits, lo=0, hi=None):
    bits = bits[lo:hi]
    return '(' + '|'.join('(unsigned)%s<<%d' % (V(b), i) for i, b in enumerate(bits)) + ')'
mid = 0
for t, n, P, par in cells:
    g = lambda k: P[k][0] if P.get(k) else ZERO
    if t in ('GND', 'VCC', 'GSR'): continue
    if t.startswith('LUT') and t[3:].isdigit():
        k = int(t[3:]); ini = num(par.get('INIT')); ins = [g('I%d' % i) for i in range(k)]
        ixe = '|'.join('%s<<%d' % (V(b), i) for i, b in enumerate(ins))
        addc([g('F')], ins, '%s=(0x%xu>>(%s))&1;' % (V(g('F')), ini, ixe))
    elif t == 'INV': addc([g('O')], [g('I')], '%s=!%s;' % (V(g('O')), V(g('I'))))
    elif t.startswith('MUX2'):
        addc([g('O')], [g('I0'), g('I1'), g('S0')], '%s=%s?%s:%s;' % (V(g('O')), V(g('S0')), V(g('I1')), V(g('I0'))))
    elif t == 'ALU':
        md = num(par.get('ALU_MODE'))
        a, b, c = V(g('I0')), V(g('I1')), V(g('CIN'))
        ai = [g('I0'), g('I1'), g('CIN')] + ([g('I3')] if md == 2 else [])   # 2 = ADDSUB
        s, co = {0: ('%s^%s' % (a, b), a), 1: ('%s^%s^1' % (a, b), a), 2: ('%s^%s^%s^1' % (a, b, V(g('I3'))), a), 3: ('%s^%s^1' % (a, b), '1'),
                 4: ('%s^%s^1' % (a, b), a), 5: ('%s^%s^1' % (a, b), b)}[md]
        code = '{int s=%s;' % s; outs = []
        if P.get('SUM'): code += '%s=s^%s;' % (V(g('SUM')), c); outs.append(g('SUM'))
        if P.get('COUT'): code += '%s=s?%s:%s;' % (V(g('COUT')), c, co); outs.append(g('COUT'))
        addc(outs, ai, code + '}')
    elif t.startswith('DFF'):
        q = V(g('Q')); d = V(g('D'))
        is_set = 'S' in t[3:] or 'P' in t[3:]
        i = num(par.get('INIT'), 1 if is_set else 0)
        if i: init.append('%s=1;' % q)
        e = d
        if 'E' in t[3:]: e = '%s?%s:%s' % (V(g('CE')), d, q)
        for pin, val in (('RESET', '0'), ('SET', '1'), ('CLEAR', '0'), ('PRESET', '1')):
            if pin in P: e = '%s?%s:(%s)' % (V(g(pin)), val, e)
        seq.append((q, e))
    elif t.startswith('RAM16S') and t[-1] in '124':
        mems.append('static uint16_t m%d[4]={%s};' % (mid, ','.join(str(num(par.get('INIT_%d' % i))) for i in range(4))))
        RA, WA = ('RAD', 'WAD') if 'SDP' in t else ('AD', 'AD')
        ad = num_expr(P[RA])
        for i in range(4):
            if len(P['DO']) > i:
                addc([P['DO'][i]], P[RA], '%s=(m%d[%d]>>%s)&1;' % (V(P['DO'][i]), mid, i, ad))
        nxt.append('if(%s){unsigned a=%s;%s}' % (V(g('WRE')), num_expr(P[WA]), ''.join(
            'm%d[%d]=(m%d[%d]&~(1<<a))|(%s<<a);' % (mid, i, mid, i, V(P['DI'][i])) for i in range(len(P['DI'])))))
        mid += 1
    elif t in ('SP', 'SDPB', 'pROM', 'pROMX9', 'SPX9'):
        x9 = t.endswith('X9')
        A, B = ('ADA', 'ADB') if t == 'SDPB' else ('AD', 'AD')
        ww = num(par.get('BIT_WIDTH_0' if t == 'SDPB' else 'BIT_WIDTH'), 32)
        rw = num(par.get('BIT_WIDTH_1'), ww) if t == 'SDPB' else ww
        if num(par.get('READ_MODE')): raise SystemExit('pipeline read ' + n)
        row = 288 if x9 else 256
        total = 0
        for i in range(64): total |= num(par.get('INIT_RAM_%02X' % i)) << (row * i)
        size = row * 64
        sh = {1: 0, 2: 1, 4: 2, 8: 3, 9: 3, 16: 4, 18: 4, 32: 5, 36: 5}
        depth = size // rw
        vals = [(total >> (rw * i)) & ((1 << rw) - 1) for i in range(depth)]
        assert rw == ww, n
        mems.append('static uint32_t m%d[%d]={%s};' % (mid, depth, ','.join(map(str, vals))))
        def adr(pin): return '(%s>>%d)' % (num_expr(P[pin]), sh[rw])
        do = [(i, b) for i, b in enumerate(P['DO'][:rw])]
        if t == 'SDPB':
            sa = '1' if 'BLKSELA' not in P else '(%s==%d)' % (num_expr(P['BLKSELA']), num(par.get('BLK_SEL_0')))
            sb = '1' if 'BLKSELB' not in P else '(%s==%d)' % (num_expr(P['BLKSELB']), num(par.get('BLK_SEL_1')))
            rd, we = '%s&&%s' % (V(g('CEB')), sb), '%s&&%s' % (V(g('CEA')), sa)
        else:
            ss = '1' if 'BLKSEL' not in P else '(%s==%d)' % (num_expr(P['BLKSEL']), num(par.get('BLK_SEL')))
            w = V(g('WRE')) if 'WRE' in P else '0'
            rd, we = '%s&&%s&&!%s' % (V(g('CE')), ss, w), '%s&&%s&&%s' % (V(g('CE')), ss, w)
        rst = V(g('RESETB' if t == 'SDPB' else 'RESET'))
        init.append('r%d=0;' % mid); mems.append('static uint32_t r%d;' % mid)
        s = 'if(%s)r%d=0; else if(%s)r%d=m%d[%s];' % (rst, mid, rd, mid, mid, adr(B))
        if 'DI' in P:
            if rw > 8 and not x9:
                assert we.endswith('&&0') or rw == 8, 'byte enables ' + n
            s += 'if(%s)m%d[%s]=%s;' % (we, mid, adr(A), num_expr(P['DI'], 0, rw))
        nxt.append(s)
        for i, b in do:
            V(b); seq_out.append((V(b), mid, i)) if False else None
        comb_ro = ''.join('%s=(r%d>>%d)&1;' % (V(b), mid, i) for i, b in do)
        seq.append(('', comb_ro)); mid += 1
    else: raise SystemExit('primitive ' + t)

# topological order
prod = {}
for k, (o, i, c) in enumerate(comb):
    for x in o: prod[x] = k
order, state = [], [0] * len(comb)
for root in range(len(comb)):
    st = [(root, iter(comb[root][1]))] if not state[root] else []
    if st: state[root] = 1
    while st:
        k, it = st[-1]
        for d in it:
            p = prod.get(d)
            if p is None or state[p] == 2: continue
            if state[p] == 1: raise SystemExit('combinational loop: ' + comb[p][2])
            state[p] = 1; st.append((p, iter(comb[p][1]))); break
        else:
            state[k] = 2; order.append(k); st.pop()

with open(outf, 'w', newline='\n') as f:
    f.write('#include <cstdint>\nstatic uint8_t v[%d];\n' % len(parent))
    f.write('\n'.join(mems) + '\n')
    f.write('static void sim_init(){%s}\n' % '\n'.join(init))
    f.write('static void eval(){\n%s\n}\n' % '\n'.join(comb[k][2] for k in order))
    regs = [(q, e) for q, e in seq if q]
    f.write('static void tick(){\nstatic uint8_t n[%d];\n' % len(regs))
    f.write('\n'.join('n[%d]=%s;' % (i, e) for i, (q, e) in enumerate(regs)) + '\n')
    f.write('\n'.join(nxt) + '\n')
    f.write('\n'.join('%s=n[%d];' % (q, i) for i, (q, e) in enumerate(regs)) + '\n')
    f.write('\n'.join(e for q, e in seq if not q) + '\n}\n')
    for n, bits in names.items():
        exp = '|'.join('(unsigned)%s<<%d' % (V(b), i) for i, b in enumerate(bits))
        f.write('static inline unsigned get_%s(){return %s;}\n' % (n, exp))
        if mods[top].dir[n] == 'input':
            f.write('static inline void set_%s(unsigned x){%s}\n' % (n, ''.join(
                'v[%d]=(x>>%d)&1;' % (find(b), i) for i, b in enumerate(bits))))
print(len(comb), 'comb', len([1 for q, _ in seq if q]), 'regs', mid, 'mems')
