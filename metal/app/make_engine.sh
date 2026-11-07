#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Compiles the mod manager for the app bundle: fifamod.py + tools -> work_mods/pkg/fifamod (a
# binary with no outside dependencies, 7zz, stock lists). Uses python.org's Python: every file it
# ships targets macOS 11. pyenv or Homebrew Python pull in Homebrew libraries built for the
# running macOS (27), which would not load on macOS 26. Checks that, and leaves no symlinks
# (the exFAT SSD cannot hold them).
set -euo pipefail
A=~/fifa_metal/app; W=$A/work_mods; E=$A/engine; cd "$W"
rm -rf eng_build pkg; mkdir -p eng_build pkg/fifamod/stock/data/ui/fonts
./pyi/bin/pyinstaller --noconfirm --onedir --name fifamod --distpath eng_build/dist --workpath eng_build/work --specpath eng_build \
    --paths "$E/tools" --hidden-import hair_ps4 --hidden-import dds_ps4 --hidden-import fifadb \
    --exclude-module tkinter --exclude-module unittest --exclude-module pydoc --exclude-module ssl --exclude-module _ssl --exclude-module hashlib --exclude-module _hashlib --exclude-module lzma --exclude-module bz2 \
    --optimize 1 "$E/fifamod.py" 2>&1 | tail -1
cp -RL eng_build/dist/fifamod pkg/fifamod/engine; rm -rf pkg/fifamod/engine/_internal/Python.framework
install -m755 "$(python3 -c 'import os;print(os.path.realpath("/opt/homebrew/bin/7zz"))')" pkg/fifamod/7zz
# RARLAB's unrar (freeware, may be distributed inside other software): 7-Zip 23 cannot read every
# RAR5 archive (FIFA Infinity Patch 9.0 main archive: "Unsupported Method"); unrar 6.12 can.
UNRAR="$(python3 -c 'import os;print(os.path.realpath("/opt/homebrew/bin/unrar"))')"
install -m755 "$UNRAR" pkg/fifamod/unrar; cp "$(dirname "$UNRAR")/license.txt" pkg/fifamod/LICENSE-unrar.txt
cp "$E/stock/data/ui/fonts/fonts.txt" pkg/fifamod/stock/data/ui/fonts/
python3 - pkg/fifamod <<'PY'
import os, re, subprocess, sys
high = (0, 0); n = 0
for d, _, fs in os.walk(sys.argv[1]):
    for f in fs:
        p = os.path.join(d, f)
        if open(p, 'rb').read(4) not in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe'): continue
        n += 1
        t = subprocess.run(['otool', '-arch', 'arm64', '-l', p], capture_output=True, text=True).stdout
        for m in re.findall(r'minos (\d+)\.(\d+)', t): high = max(high, (int(m[0]), int(m[1])))
        for l in subprocess.run(['otool', '-arch', 'arm64', '-L', p], capture_output=True, text=True).stdout.split('\n')[1:]:
            assert not l.strip() or re.match(r'\s*(/usr/lib|/System|@)', l), (p, l)
assert high < (26, 0), f'a file needs macOS {high}'
print(f'{n} binaries, highest minimum macOS {high[0]}.{high[1]}, no outside libraries')
PY
