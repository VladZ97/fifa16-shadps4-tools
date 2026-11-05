#!/bin/zsh
# Installs the hybrid build as launcher version "Custom-metal" (Custom-perf and Custom-flipfix untouched).
set -e
SRC="$HOME/fifa_metal/shadps4-metal/build"; DST="$HOME/Library/Application Support/shadPS4QtLauncher/versions/Custom-metal"
mkdir -p "$DST"
for f in shadps4 libvulkan.dylib libvulkan_kosmickrisp.dylib kosmickrisp_mesa_icd.json; do cp "$SRC/$f" "$DST/"; done
chmod +x "$DST/shadps4"
install_name_tool -change @rpath/libz.1.dylib /usr/lib/libz.1.dylib "$DST/libvulkan_kosmickrisp.dylib" 2>/dev/null || true
codesign -s - -f "$DST/libvulkan_kosmickrisp.dylib" >/dev/null 2>&1 || true
echo "installed to $DST"; otool -L "$DST/shadps4" | grep -i bbgpu
