#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# The app with the Mods page: the last released bundle (out26) with only these replaced: the
# launcher executable, run.sh and Resources/fifamod (compiled engine, 7zz, stock lists). The
# emulator, GPU hosts and libraries stay byte for byte as released.
#   bash make_mods_app.sh <version>     -> ~/fifa_metal/app/out_mods
set -euo pipefail
ver=${1:?version}; A=~/fifa_metal/app; W=$A/work_mods; OUT=$A/out_mods
rm -rf "$OUT"; mkdir -p "$OUT"; cp -R "$A/out26/FIFA 16.app" "$OUT/"
APP="$OUT/FIFA 16.app"; RES="$APP/Contents/Resources"
install -m755 ~/fifa_metal/launcher/out/FIFA16Launcher "$APP/Contents/MacOS/FIFA 16"
install -m755 "$A/run.sh" "$RES/run.sh"
rm -rf "$RES/fifamod"; cp -R "$W/pkg/fifamod" "$RES/fifamod"
cp "$A/engine/README.md" "$RES/fifamod/README.md"
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP" && echo "signature ok"
[ -z "$(find "$APP" -type l)" ] && echo "no symlinks (exFAT safe)"
(cd "$OUT" && ditto -c -k --keepParent "FIFA 16.app" "FIFA16-macOS-$ver.zip" && du -sh "FIFA 16.app" "FIFA16-macOS-$ver.zip")
