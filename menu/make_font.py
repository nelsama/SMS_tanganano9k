#!/usr/bin/env python3
"""make_font.py out.c : font.s -> C array (characters 32..127)."""
import re, sys, os
p = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'rom', 'font.s')
f = [int(x, 16) for l in open(p) if '.byte' in l for x in re.findall(r'\$([0-9a-fA-F]{2})', l)][256:1024]
open(sys.argv[1], 'w').write('const unsigned char font[768] = {%s};\n' % ','.join(map(str, f)))
