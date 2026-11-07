#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# fifa-hybrid: F16.app with the macOS 26 GPU host path: the plain bbgpu-host (rebuilt: takeover +
# re-exec), bbgpu-host-macos26 (stub with the pinned ranges) and libbbhost.dylib added to the GPU host
# app. Emulator, bbgpu-host-macos27 and libbbgpu.dylib are the files of the base app, untouched.
#   bash make_host26_app.sh <version> [base app] [--no-macos27]   -> ~/fifa_metal/app/out_host26/
# --no-macos27 drops bbgpu-host-macos27 so the plain host (and its re-exec) runs on this Mac (testing).
set -euo pipefail
ver=${1:?version}; BASE=${2:-$HOME/fifa_metal/app/out_host26/F16.app}; NO27=${3:-}
B=~/fifa_metal/fifa16_mac_port; OUT=~/fifa_metal/app/out_host26; rm -rf "$OUT"; mkdir -p "$OUT"
cp -R "$BASE" "$OUT/F16.app"; APP="$OUT/F16.app"
# The GPU helper is "F16 GPU.app"; a base built before the rename is converted here.
if [ -d "$APP/Contents/Helpers/FIFA 16 GPU.app" ]; then mv "$APP/Contents/Helpers/FIFA 16 GPU.app" "$APP/Contents/Helpers/F16 GPU.app"; fi
cp "$HOME/fifa_metal/host_app/F16 GPU.app/Contents/Info.plist" "$APP/Contents/Helpers/F16 GPU.app/Contents/Info.plist"
HM="$APP/Contents/Helpers/F16 GPU.app/Contents/MacOS"
cp "$B/out/bbgpu-host" "$B/out/bbgpu-host-macos26" "$B/out/gpu-arm64/libbbhost.dylib" "$HM/"
cp "$HOME/fifa_metal/app/run.sh" "$APP/Contents/Resources/run.sh"; chmod +x "$APP/Contents/Resources/run.sh"   # in-process fallback
for f in "$HM/bbgpu-host" "$HM/bbgpu-host-macos26" "$HM/libbbhost.dylib"; do
    for rp in $(otool -l "$f" | awk '/LC_RPATH/{getline; getline; print $2}'); do
        case "$rp" in @*) ;; *) install_name_tool -delete_rpath "$rp" "$f" ;; esac
    done
    otool -l "$f" | grep -q '@executable_path' || install_name_tool -add_rpath @executable_path "$f"
    chmod +x "$f"
done
otool -l "$HM/libbbhost.dylib" | grep -q '@loader_path' || install_name_tool -add_rpath @loader_path "$HM/libbbhost.dylib"
[ "$NO27" = "--no-macos27" ] && rm -f "$HM/bbgpu-host-macos27"
if [ "${WITH_ENGINE:-}" = 1 ]; then rm -rf "$APP/Contents/Resources/fifamod"; cp -R ~/fifa_metal/app/work_mods/pkg/fifamod "$APP/Contents/Resources/fifamod"; cp ~/fifa_metal/app/engine/README.md "$APP/Contents/Resources/fifamod/" 2>/dev/null; echo "mod engine replaced"; fi
if [ "${WITH_LAUNCHER:-}" = 1 ]; then rm -f "$APP/Contents/MacOS/FIFA 16"; install -m755 ~/fifa_metal/launcher/out/FIFA16Launcher "$APP/Contents/MacOS/F16"; cp ~/fifa_metal/launcher/F16.app/Contents/Info.plist "$APP/Contents/Info.plist"; echo "launcher replaced"; fi
if [ "${WITH_EMULATOR:-}" = 1 ]; then   # the rebuilt emulator (shadps4-metal/build), rpaths made bundle-relative as make_app.sh does
    EMU="$APP/Contents/Resources/emulator"; cp ~/fifa_metal/shadps4-metal/build/shadps4 "$EMU/shadps4"
    for rp in $(otool -l "$EMU/shadps4" | awk '/LC_RPATH/{getline; getline; print $2}'); do
        case "$rp" in @*) ;; *) install_name_tool -delete_rpath "$rp" "$EMU/shadps4" ;; esac
    done
    otool -l "$EMU/shadps4" | grep -q '@executable_path' || install_name_tool -add_rpath @executable_path "$EMU/shadps4"
    chmod +x "$EMU/shadps4"; echo "emulator replaced from shadps4-metal/build"
fi
# No game artwork in the bundle: the app's own icon (launcher/art), no banner (the launcher shows the
# game's header art from the user's game folder at runtime); third-party licence texts.
cp ~/fifa_metal/launcher/art/FIFA16.icns "$APP/Contents/Resources/FIFA16.icns"; rm -f "$APP/Contents/Resources/banner.jpg"
rm -rf "$APP/Contents/Resources/Licenses"; cp -R ~/fifa_metal/app/licenses "$APP/Contents/Resources/Licenses"
cp ~/fifa_metal/app/NOTICE "$APP/Contents/Resources/NOTICE"
# SOURCES.txt: the exact commits this build was made from (GPL corresponding source)
{ echo "F16.app $ver - corresponding source"; echo; echo "fifa16_mac_port (libbbgpu, bbgpu-host*, libbbhost)  https://github.com/VladZ97/fifa16_mac_port  $(git -C ~/fifa_metal/bloodborne_mac_port rev-parse HEAD)";
  echo "shadps4-fifa (emulator)                           https://github.com/VladZ97/shadps4-fifa     $(git -C ~/fifa_metal/shadps4-metal rev-parse HEAD)";
  echo "fifa16-shadps4-tools (launcher, run.sh, scripts)  https://github.com/VladZ97/fifa16-shadps4-tools  $(git -C ~/fifa16-shadps4-tools rev-parse HEAD)";
  echo "fifa16-mods (fifamod engine)                      https://github.com/VladZ97/fifa16-mods      $(git -C ~/FIFA16Mods rev-parse HEAD)";
  echo; echo "Each repository carries the tag $ver at the commit above. Third-party versions: see Licenses/README.md."; } > "$APP/Contents/Resources/SOURCES.txt"
rm -rf "$APP/Contents/Helpers/F16 GPU.app/Contents/_CodeSignature"
xattr -cr "$APP" 2>/dev/null || true
find "$APP" -name "._*" -delete   # AppleDouble files a base copied from exFAT brings along (they break signing)
codesign --force --deep -s - "$APP"; codesign --verify --deep --strict "$APP" && echo "signature ok"
for f in "$HM/bbgpu-host" "$HM/bbgpu-host-macos26" "$HM/libbbhost.dylib"; do
    otool -l "$f" | awk '/LC_RPATH/{getline; getline; print $2}' | grep -v '^@' && { echo "outside rpath in $f"; exit 1; }
done
# The stub must take libbbhost and libbbgpu from the bundle (SDL/ffmpeg: the bundled libbbgpu.dylib
# still carries this Mac's deps rpath, so here they come from there, as in the shipped app).
DYLD_PRINT_LIBRARIES=1 "$HM/bbgpu-host-macos26" 2>&1 | grep -E "dyld\[.*\]: <" | sed 's/.*> //' | grep "libbb" | grep -v "F16 GPU.app" && { echo "libbb* outside the bundle"; exit 1; }
"$HM/bbgpu-host-macos26" 2>&1 | head -2 || true
(cd "$OUT" && rm -f "F16-macOS-$ver.zip" && ditto -c -k --norsrc --keepParent "F16.app" "F16-macOS-$ver.zip" && du -sh "F16-macOS-$ver.zip" | cut -f1)
