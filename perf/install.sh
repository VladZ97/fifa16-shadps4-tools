#!/bin/zsh
# Installs the side build as launcher version "Custom-perf" (the working "Custom-flipfix" is left alone).
set -e
SRC="$HOME/fifa_perf/shadps4/build"; DST="$HOME/Library/Application Support/shadPS4QtLauncher/versions/Custom-perf"
mkdir -p "$DST"
for f in shadps4 libvulkan.dylib libvulkan_kosmickrisp.dylib kosmickrisp_mesa_icd.json; do cp "$SRC/$f" "$DST/"; done
chmod +x "$DST/shadps4"
install_name_tool -change @rpath/libz.1.dylib /usr/lib/libz.1.dylib "$DST/libvulkan_kosmickrisp.dylib" 2>/dev/null || true
codesign -s - -f "$DST/libvulkan_kosmickrisp.dylib" >/dev/null 2>&1 || true
echo "installed to $DST"
