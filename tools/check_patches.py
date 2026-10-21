#!/usr/bin/env python3
"""Check lib/patches/ against the trees it was generated from.

    tools/check_patches.py <engine checkout> <base ref> <co-op ref>

For every unit: the edits applied to the base ref's function must give the
co-op ref's function byte for byte; and they must still land when upstream
has changed the function (simulated by a line slipped in after its header).
Runs tools/check_patches.lua under luajit.
"""
import os, subprocess, sys, tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from luaunits import units  # noqa: E402
from gen_patches import MODULES, show, HERE  # noqa: E402


def long_str(s):
    level = 1
    while (']' + '=' * level + ']') in s:
        level += 1
    return '[' + '=' * level + '[' + s + ']' + '=' * level + ']'


def keyed(us):
    seen, out = {}, {}
    for u in us:
        n = seen.get(u['name'], 0)
        seen[u['name']] = n + 1
        out[(u['name'], n)] = u
    return out


def main():
    repo, base_ref, coop_ref = sys.argv[1:4]
    out = ['return {']
    for path, _, _, _ in MODULES:
        bu, _ = units(show(repo, base_ref, path))
        nu, _ = units(show(repo, coop_ref, path))
        stem = os.path.splitext(os.path.basename(path))[0]
        out.append(' [%r] = {' % stem)
        bk = keyed(bu)
        for (name, n), u in keyed(nu).items():
            b = bk.get((name, n))
            out.append('  [%r] = { new = %s, base = %s },' % (
                name, long_str(u['text']), long_str(b['text']) if b else 'nil'))
        out.append('  _all = {')
        first = {}
        for u in bu:
            first.setdefault(u['name'], u)
        for name, u in first.items():
            out.append('   [%r] = %s,' % (name, long_str(u['text'])))
        out.append('  },')
        out.append(' },')
    out.append('}')
    with tempfile.NamedTemporaryFile('w', suffix='.lua', delete=False,
                                     encoding='latin-1', newline='\n') as f:
        f.write('\n'.join(out) + '\n')
        expect = f.name
    try:
        r = subprocess.run(['luajit', os.path.join(HERE, 'tools', 'check_patches.lua'), expect],
                           cwd=HERE)
    finally:
        os.remove(expect)
    sys.exit(r.returncode)


if __name__ == '__main__':
    main()
