#!/bin/bash
# Assembles the self-contained FIFA 16.app: the launcher (launcher/build.sh), the emulator and its
# libraries, the GPU library and host, run.sh, settings, fifamod. Fixes the library search paths
# so nothing points outside the bundle, signs it ad hoc and zips it.
#   bash make_app.sh <version>      -> ~/fifa_metal/app/out/FIFA 16.app and FIFA16-macOS-<version>.zip
set -euo pipefail
ver=${1:?version, e.g. v0.3.0}
HERE=$(cd "$(dirname "$0")" && pwd); OUT="$HERE/out"; rm -rf "$OUT"; mkdir -p "$OUT"
L=~/fifa_metal/launcher; S=~/fifa_metal/shadps4-metal/build; B=~/fifa_metal/bloodborne_mac_port
LIBS=(libSDL3.0.dylib libavformat.61.dylib libavcodec.61.dylib libswscale.8.dylib libswresample.5.dylib libavutil.59.dylib)

echo "== launcher"; (cd "$L" && bash build.sh >/dev/null); cp -R "$L/FIFA 16.app" "$OUT/"
rm -rf "$L/FIFA 16.app"   # the skeleton has no payload: never leave it around to be opened by mistake
APP="$OUT/FIFA 16.app"; RES="$APP/Contents/Resources"; EMU="$RES/emulator"; HLP="$APP/Contents/Helpers"
mkdir -p "$EMU" "$HLP" "$RES/fifamod/tools" "$RES/fifamod/stock/data/ui/fonts"

echo "== emulator (x86-64) + libraries"
cp "$S/shadps4" "$S/libvulkan.dylib" "$S/libvulkan_kosmickrisp.dylib" "$S/kosmickrisp_mesa_icd.json" "$EMU/"
cp "$B/out/gpu/libbbgpu.dylib" "$EMU/"; for l in "${LIBS[@]}"; do cp "$B/deps/x86_64/lib/$l" "$EMU/"; done
for rp in $(otool -l "$EMU/shadps4" | awk '/LC_RPATH/{getline; getline; print $2}'); do
    case "$rp" in @*) ;; *) install_name_tool -delete_rpath "$rp" "$EMU/shadps4" ;; esac
done
otool -l "$EMU/shadps4" | grep -q '@executable_path' || install_name_tool -add_rpath @executable_path "$EMU/shadps4"
install_name_tool -change @rpath/libz.1.dylib /usr/lib/libz.1.dylib "$EMU/libvulkan_kosmickrisp.dylib" 2>/dev/null || true
chmod +x "$EMU/shadps4"

echo "== GPU host app (arm64) + libraries"
cp -R "$HOME/fifa_metal/host_app/FIFA 16 GPU.app" "$HLP/"; HM="$HLP/FIFA 16 GPU.app/Contents/MacOS"
cp "$B/out/bbgpu-host" "$B/out/bbgpu-host-macos27" "$HM/"; cp "$B/out/gpu-arm64/libbbgpu.dylib" "$HM/"; for l in "${LIBS[@]}"; do cp "$B/deps/arm64/lib/$l" "$HM/"; done
for h in "$HM/bbgpu-host" "$HM/bbgpu-host-macos27"; do
    for rp in $(otool -l "$h" | awk '/LC_RPATH/{getline; getline; print $2}'); do
        case "$rp" in @*) ;; *) install_name_tool -delete_rpath "$rp" "$h" ;; esac
    done
    otool -l "$h" | grep -q '@executable_path' || install_name_tool -add_rpath @executable_path "$h"
    chmod +x "$h"
done
rm -rf "$HLP/FIFA 16 GPU.app/Contents/_CodeSignature"

echo "== run logic, settings, mod manager"
cp "$HERE/run.sh" "$RES/run.sh"; chmod +x "$RES/run.sh"; cp ~/fifa_metal/bbport.ini "$RES/bbport.ini"
python3 - "$HOME/Library/Application Support/shadPS4QtLauncher/versions/Custom-metal/user/config.json" "$RES/config.template.json" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
c["General"]["install_dirs"] = []; c["General"]["addon_install_dir"] = ""; c["General"]["home_dir"] = ""
c["Log"]["filter"] = "*:error"
s = json.dumps(c, indent=4); assert "/Users/" not in s and "/Volumes/" not in s, "personal path in template"
open(sys.argv[2], "w").write(s)
PY
cp ~/FIFA16Mods/fifamod.py ~/FIFA16Mods/README.md "$RES/fifamod/"; cp ~/FIFA16Mods/tools/hair_ps4.py ~/FIFA16Mods/tools/dds_ps4.py ~/FIFA16Mods/tools/fifadb.py "$RES/fifamod/tools/"; cp ~/FIFA16Mods/stock/data/ui/fonts/fonts.txt "$RES/fifamod/stock/data/ui/fonts/"
cp "$B/LICENSE" "$RES/LICENSE-bloodborne_mac_port.txt"

echo "== sign"
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP" && echo "signature ok"
echo "== smoke: the bundled emulator resolves its libraries"
if arch -x86_64 "$EMU/shadps4" --help >/dev/null 2>"$OUT/smoke.err"; then echo "emulator loads"; else grep -m2 -i 'dyld\|library' "$OUT/smoke.err" || true; fi
du -sh "$APP" | cut -f1
(cd "$OUT" && rm -f "FIFA16-macOS-$ver.zip" && ditto -c -k --keepParent "FIFA 16.app" "FIFA16-macOS-$ver.zip" && du -sh "FIFA16-macOS-$ver.zip" | cut -f1)
