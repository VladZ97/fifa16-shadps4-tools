#!/bin/bash
# Builds the self-contained release bundle (everything except the game) from the installed setup.
#   bash make_bundle.sh <version>      -> ./FIFA16-macOS-<version>.zip
# Sources: the installed Custom-metal emulator, ~/fifa_metal (run.sh, bbport.ini, host app, fixers),
# ~/fifa_metal/bloodborne_mac_port (libbbgpu x86_64+arm64, host, the six runtime dylibs), ~/FIFA16Mods.
set -euo pipefail
ver=${1:?version, e.g. v0.2.0}; here=$(cd "$(dirname "$0")" && pwd)
R=$PWD/FIFA16-macOS-$ver; P=$R/payload; V="$HOME/Library/Application Support/shadPS4QtLauncher/versions/Custom-metal"; B=$HOME/fifa_metal/bloodborne_mac_port
rm -rf "$R"; mkdir -p "$P/fifa_metal/host_app" "$P/fifa_metal/launcher" "$P/bloodborne_mac_port/out/gpu" "$P/bloodborne_mac_port/out/gpu-arm64" "$P/bloodborne_mac_port/deps/x86_64/lib" "$P/bloodborne_mac_port/deps/arm64/lib" "$P/Custom-metal/user/download/CUSA02138" "$P/Custom-metal/user/cache" "$P/FIFA16Mods/tools" "$P/FIFA16Mods/stock/data/ui/fonts"
cp ~/fifa_metal/run.sh ~/fifa_metal/bbport.ini ~/fifa_metal/install.sh ~/fifa_metal/fix_ball_meshes.py ~/fifa_metal/fix_ball_textures.py ~/fifa_metal/stripify_balls.py "$P/fifa_metal/"
cp -R "$HOME/fifa_metal/host_app/FIFA 16 GPU.app" "$P/fifa_metal/host_app/"; cp ~/fifa_metal/host_app/refresh.sh ~/fifa_metal/host_app/README.md "$P/fifa_metal/host_app/"; cp "$HOME/fifa_metal/launcher/FIFA 16.command" "$P/fifa_metal/launcher/"
cp "$B/out/gpu/libbbgpu.dylib" "$P/bloodborne_mac_port/out/gpu/"; cp "$B/out/gpu-arm64/libbbgpu.dylib" "$P/bloodborne_mac_port/out/gpu-arm64/"; cp "$B/out/bbgpu-host" "$B/out/bbgpu-host-macos27" "$P/bloodborne_mac_port/out/"; cp "$B/LICENSE" "$P/bloodborne_mac_port/"
for arch in x86_64 arm64; do for lib in libSDL3.0.dylib libavformat.61.dylib libavcodec.61.dylib libswscale.8.dylib libswresample.5.dylib libavutil.59.dylib; do cp "$B/deps/$arch/lib/$lib" "$P/bloodborne_mac_port/deps/$arch/lib/"; done; done
cp "$V/shadps4" "$V/libvulkan.dylib" "$V/libvulkan_kosmickrisp.dylib" "$V/kosmickrisp_mesa_icd.json" "$P/Custom-metal/"
python3 - "$V/user/config.json" "$P/Custom-metal/user/config.json.template" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
c["General"]["install_dirs"] = [{"enabled": True, "path": "__GAME_DIR__"}]
c["General"]["addon_install_dir"] = "__HOME__/Library/Application Support/shadPS4/addcont"
c["Log"]["filter"] = "*:error"
s = json.dumps(c, indent=4); assert "/Users/" not in s and "/Volumes/" not in s
open(sys.argv[2], "w").write(s)
PY
cp ~/FIFA16Mods/fifamod.py ~/FIFA16Mods/README.md "$P/FIFA16Mods/"; cp ~/FIFA16Mods/tools/hair_ps4.py ~/FIFA16Mods/tools/dds_ps4.py ~/FIFA16Mods/tools/fifadb.py "$P/FIFA16Mods/tools/"; cp ~/FIFA16Mods/stock/data/ui/fonts/fonts.txt "$P/FIFA16Mods/stock/data/ui/fonts/"
bash ~/fifa_metal/launcher/build.sh >/dev/null && cp -R "$HOME/fifa_metal/launcher/FIFA 16.app" "$R/"
cp "$here/install.sh" "$here/README.txt" "$R/"; chmod +x "$R/install.sh"
rm -f "$R.zip"; ditto -c -k --keepParent "$R" "$R.zip"; du -sh "$R.zip"
