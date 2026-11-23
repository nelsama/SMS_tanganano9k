#!/usr/bin/env python3
"""make_data.py : gfx.bin (tiles 128..133, 4 planes) and font.bin (from font.s)."""
import re, os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
def tile(rows):
    o = []
    for r in rows:
        for p in range(4): o.append(sum(((c >> p) & 1) << (7 - i) for i, c in enumerate(r)))
    return o
def ball(x0, y0):
    rows = []
    for y in range(y0, y0 + 8):
        r = []
        for x in range(x0, x0 + 8):
            d = (x - 7.5) ** 2 + (y - 7.5) ** 2
            l = (x - 5) ** 2 + (y - 5) ** 2
            r.append(0 if d > 60 else 1 if l < 6 else 5 if l < 40 else 13)
        rows.append(r)
    return tile(rows)
g = tile([[0] * 8] * 8)
g += tile([[(x // 2) + 2 if y < 6 else 0 for x in range(8)] for y in range(8)])
g += tile([[6 if x in (0, 7) or y in (0, 7) else 0 for x in range(8)] for y in range(8)])
g += tile([[2] * 8] * 8)
g += ball(0, 0) + ball(0, 8) + ball(8, 0) + ball(8, 8)
open('gfx.bin', 'wb').write(bytes(g))
f = [int(x, 16) for l in open('font.s') if '.byte' in l for x in re.findall(r'\$([0-9a-fA-F]{2})', l)]
open('font.bin', 'wb').write(bytes(f[32 * 8:96 * 8]))
