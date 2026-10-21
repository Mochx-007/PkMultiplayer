#!/usr/bin/env python3
"""Split a Gen2Recomped engine file into top-level units.

The engine keeps every top-level function at column 0 and closes it with an
`end` at column 0, so a unit is `function X.y(` / `function X:y(` /
`local function y(` / `X.y = function(` up to that `end`.  Everything else is
"loose" top-level code (locals, tables, assignments).
"""
import re, sys, hashlib

FUNC = re.compile(r'^(?:(local)\s+function\s+([A-Za-z_][\w]*)'
                  r'|function\s+([A-Za-z_][\w.:]*)'
                  r'|([A-Za-z_][\w.\[\]"\']*)\s*=\s*function\b)')

def units(text):
    lines = text.split('\n')
    out, loose, i = [], [], 0
    while i < len(lines):
        m = FUNC.match(lines[i])
        if m:
            if m.group(1):
                name, kind = m.group(2), 'local'
            elif m.group(3):
                name, kind = m.group(3), 'method' if ':' in m.group(3) else 'field'
            else:
                name, kind = m.group(4), 'assign'
            j = i
            # one-liner `function x() ... end`
            if not re.search(r'\bend\s*$', lines[i]) or lines[i].count('function') == 0:
                j = i + 1
                while j < len(lines) and not re.match(r'^end\b', lines[j]):
                    j += 1
            elif kind == 'assign' or True:
                # a one-line body only when the line closes itself
                if not re.match(r'^.*\bfunction\b.*\bend\s*\)?\s*$', lines[i]):
                    j = i + 1
                    while j < len(lines) and not re.match(r'^end\b', lines[j]):
                        j += 1
            body = '\n'.join(lines[i:j + 1])
            out.append({'name': name, 'kind': kind, 'start': i + 1, 'end': j + 1,
                        'text': body})
            i = j + 1
        else:
            loose.append((i + 1, lines[i]))
            i += 1
    return out, loose

def sha(s):
    return hashlib.sha1(s.encode('utf-8', 'surrogateescape')).hexdigest()[:12]

if __name__ == '__main__':
    us, _ = units(open(sys.argv[1], encoding='latin-1').read())
    for u in us:
        print(u['kind'], u['name'], u['start'], u['end'])
