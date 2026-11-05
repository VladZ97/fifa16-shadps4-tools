#!/bin/bash
# FIFA 16 on Apple Silicon (shadPS4 Metal hybrid) - installs everything except the game.
#   bash install.sh --game "<folder that contains CUSA02138 and CUSA02138-UPDATE>"
#   bash install.sh            (asks for the folder)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
GAME_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --game) GAME_DIR="$2"; shift 2 ;;
    -h|--help) sed -n 2,4p "$0"; exit 0 ;;
    *) echo "unknown option $1"; exit 1 ;;
  esac
done
say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

say "Checking the Mac"
[ "$(uname -m)" = arm64 ] || die "this build needs an Apple Silicon Mac"
major=$(sw_vers -productVersion | cut -d. -f1); [ "$major" -ge 15 ] || die "macOS 15 or newer required (found $(sw_vers -productVersion))"
if ! arch -x86_64 /usr/bin/true 2>/dev/null; then
  say "Rosetta 2 is missing - installing (the emulator is an x86-64 program)"
  softwareupdate --install-rosetta --agree-to-license
fi
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import json' 2>/dev/null; then
  echo "python3 is needed (run.sh and fifamod use it). Install the Command Line Tools: xcode-select --install"
  exit 1
fi

say "Game folder"
while [ ! -f "$GAME_DIR/CUSA02138/eboot.bin" ]; do
  [ -n "$GAME_DIR" ] && echo "  $GAME_DIR/CUSA02138/eboot.bin not found"
  printf 'Folder that contains CUSA02138 (and CUSA02138-UPDATE): '
  read -r GAME_DIR
  GAME_DIR=${GAME_DIR/#\~/$HOME}; GAME_DIR=${GAME_DIR%/}
done
GAME_DIR=$(cd "$GAME_DIR" && pwd)
[ -d "$GAME_DIR/CUSA02138-UPDATE" ] || echo "  note: CUSA02138-UPDATE (update 1.07) not found next to the game; the base game runs, 1.07 is recommended"
mkdir -p "$GAME_DIR/CUSA02138-mods"

say "Installing"
V="$HOME/Library/Application Support/shadPS4QtLauncher/versions/Custom-metal"
mkdir -p "$HOME/fifa_metal" "$V/user/download/CUSA02138" "$V/user/cache" "$HOME/Applications"
if [ -f "$HOME/fifa_metal/run.sh" ] && ! cmp -s "$HOME/fifa_metal/run.sh" "$here/payload/fifa_metal/run.sh"; then
  cp "$HOME/fifa_metal/run.sh" "$HOME/fifa_metal/run.sh.bak-$(date +%Y%m%d%H%M)"; echo "  existing run.sh backed up"
fi
ditto "$here/payload/fifa_metal" "$HOME/fifa_metal"
ditto "$here/payload/bloodborne_mac_port" "$HOME/fifa_metal/bloodborne_mac_port"
for f in shadps4 libvulkan.dylib libvulkan_kosmickrisp.dylib kosmickrisp_mesa_icd.json; do cp "$here/payload/Custom-metal/$f" "$V/"; done
chmod +x "$V/shadps4" "$HOME/fifa_metal/run.sh" "$HOME/fifa_metal/host_app/FIFA 16 GPU.app/Contents/MacOS/"*
ditto "$here/payload/FIFA16Mods" "$HOME/FIFA16Mods"
rm -rf "$HOME/Applications/FIFA 16.app"; ditto "$here/FIFA 16.app" "$HOME/Applications/FIFA 16.app"

say "Pointing everything at the game"
python3 - "$HOME/fifa_metal/run.sh" "$GAME_DIR/CUSA02138/eboot.bin" <<'PY'
import re, sys
p, eboot = sys.argv[1], sys.argv[2]
s = open(p).read()
s2, n = re.subn(r'^GAME="\$\{SIDE_GAME:-[^}]*\}"', 'GAME="${SIDE_GAME:-%s}"' % eboot, s, count=1, flags=re.M)
assert n == 1, "GAME= line not found in run.sh"
open(p, "w").write(s2)
PY
if [ -f "$V/user/config.json" ]; then
  echo "  keeping the existing $V/user/config.json (install_dirs not changed)"
else
  sed -e "s#__GAME_DIR__#$GAME_DIR#g" -e "s#__HOME__#$HOME#g" "$here/payload/Custom-metal/user/config.json.template" > "$V/user/config.json"
fi

say "Clearing the download quarantine and signing"
for p in "$HOME/fifa_metal" "$V" "$HOME/FIFA16Mods" "$HOME/Applications/FIFA 16.app"; do xattr -dr com.apple.quarantine "$p" 2>/dev/null || true; done
codesign --force -s - "$V/shadps4" "$V/libvulkan.dylib" "$V/libvulkan_kosmickrisp.dylib" 2>/dev/null || true
find "$HOME/fifa_metal/bloodborne_mac_port" -name '*.dylib' -o -name 'bbgpu-host*' -type f | while read -r f; do codesign --force -s - "$f" 2>/dev/null || true; done
codesign --force --deep -s - "$HOME/fifa_metal/host_app/FIFA 16 GPU.app" 2>/dev/null || true
codesign --force --deep -s - "$HOME/Applications/FIFA 16.app" 2>/dev/null || true

if [ -d /opt/homebrew/bin ] && [ -w /opt/homebrew/bin ]; then
  printf '#!/bin/sh\nexec python3 -I "$HOME/FIFA16Mods/fifamod.py" "$@"\n' > /opt/homebrew/bin/fifamod && chmod +x /opt/homebrew/bin/fifamod && echo "  fifamod command installed (/opt/homebrew/bin/fifamod)"
fi

say "Done"
cat <<MSG
  Launcher:  ~/Applications/FIFA 16.app   (right-click > Open the first time)
  Terminal:  bash ~/fifa_metal/run.sh play
  Logs:      ~/fifa_metal/runs/<timestamp>/emulator.log
  The first start takes a minute (Rosetta translates the emulator once); the first sessions
  compile shaders into the cache and stutter a little, then it settles at 60 fps.
  Patches/mods: see ~/FIFA16Mods/README.md (fifamod init / install).
MSG
