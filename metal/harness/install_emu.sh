#!/bin/bash
# install_emu.sh : installs the built emulator into the harness slot, signed with get-task-allow.
S=${S:-${TMPDIR:-/tmp}/fifa_harness}; mkdir -p "$S"   # scratch folder for logs and intermediate files
D="$HOME/Library/Application Support/shadPS4QtLauncher/versions/Custom-metal"
pgrep -x shadps4 >/dev/null && { echo "emulator running"; exit 1; }
cp ~/fifa_metal/shadps4-metal/build/shadps4 "$D/shadps4" && chmod +x "$D/shadps4" && codesign --force --sign - --entitlements $S/get-task-allow.plist "$D/shadps4" 2>/dev/null
codesign -d --entitlements - "$D/shadps4" 2>&1 | grep -q get-task-allow && echo "installed + signed: $(stat -f %z "$D/shadps4") bytes"
