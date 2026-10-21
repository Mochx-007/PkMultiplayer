#!/usr/bin/env python3
"""Build the release zip: tools/pack.py [-o out.zip]

What `modkit pack` would ship -- every tracked file except those listed in
.modkitignore and the dotfiles -- with the manifest at the zip root, so the
launcher's Import mod .zip takes it.  (modkit pack itself refuses this mod:
its headless validator crashes on any mod declaring `required_imports`,
src/mods/ModImports needs LOVE's filesystem.)  Reproducible: sorted entries,
fixed timestamps.
"""
import json, os, subprocess, sys, zipfile

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    version = json.load(open(os.path.join(HERE, 'manifest.json')))['version']
    out = os.path.join(HERE, f'PkMultiplayer-{version}.zip')
    if '-o' in sys.argv:
        out = sys.argv[sys.argv.index('-o') + 1]
    ignored = set()
    with open(os.path.join(HERE, '.modkitignore')) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                ignored.add(line)
    files = subprocess.run(['git', '-C', HERE, 'ls-files'], check=True,
                           capture_output=True, text=True).stdout.split()
    files = sorted(f for f in files if f not in ignored and not os.path.basename(f).startswith('.'))
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for rel in files:
            info = zipfile.ZipInfo(rel, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            with open(os.path.join(HERE, rel), 'rb') as f:
                z.writestr(info, f.read())
    print(f'wrote {out} ({len(files)} files)')


if __name__ == '__main__':
    main()
