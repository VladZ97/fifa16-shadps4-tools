#!/bin/bash
# Candidate app = the released v0.3.0 app with ONE file replaced: the plain GPU host (the one the
# emulator starts before macOS 27). Everything else is copied as is; then the bundle is re-signed
# the way make_app.sh does. Output: ~/fifa_metal/app/out26/FIFA 16.app and FIFA16-macOS-<ver>.zip
set -euo pipefail
ver=${1:?version}; W=~/fifa_metal/app/work26; OUT=~/fifa_metal/app/out26
BASE="$HOME/fifa_metal/app/out/FIFA 16.app"; NEWHOST="$W/build/bbgpu-host"
rm -rf "$OUT"; mkdir -p "$OUT"; cp -R "$BASE" "$OUT/"
APP="$OUT/FIFA 16.app"; HM="$APP/Contents/Helpers/FIFA 16 GPU.app/Contents/MacOS"
cp "$NEWHOST" "$HM/bbgpu-host"; chmod +x "$HM/bbgpu-host"
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP" && echo "signature ok"
(cd "$OUT" && ditto -c -k --keepParent "FIFA 16.app" "FIFA16-macOS-$ver.zip" && du -sh "FIFA16-macOS-$ver.zip" | cut -f1)
