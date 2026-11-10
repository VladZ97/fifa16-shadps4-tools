#!/bin/zsh
# Installs the custom-built shadPS4 next to the launcher's versions as "Custom-flipfix" and points ~/fifa_run.sh at it.
set -e
SRC="${FIFA_SCRATCH:?set FIFA_SCRATCH to the build scratch folder}/build/shadps4/build"
DST="$HOME/Library/Application Support/shadPS4QtLauncher/versions/Custom-flipfix"
mkdir -p "$DST"
for f in shadps4 libvulkan.dylib libvulkan_kosmickrisp.dylib kosmickrisp_mesa_icd.json; do cp "$SRC/$f" "$DST/"; done
chmod +x "$DST/shadps4"
# the mesa build links zlib via @rpath, which the emulator cannot resolve; point it at the system zlib
install_name_tool -change @rpath/libz.1.dylib /usr/lib/libz.1.dylib "$DST/libvulkan_kosmickrisp.dylib" 2>/dev/null || true
codesign -s - -f "$DST/libvulkan_kosmickrisp.dylib" >/dev/null 2>&1 || true
sed -i '' 's#^EMU=.*#EMU="'"$DST"'/shadps4"#' "$HOME/fifa_run.sh"
echo "installed to $DST"; grep '^EMU=' "$HOME/fifa_run.sh"
