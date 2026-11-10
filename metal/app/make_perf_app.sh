#!/bin/bash
# make_perf_app.sh <version> [base app]: patches a base bundle (default out_host26/F16.app = v0.5.0) with the
# rebuilt renderer (libbbgpu arm64 + x86, libbbhost, the three hosts) and run.sh -> out_perf/.
# OUT=<dir> picks another output folder (the 0.5.1-b to -i development rounds used out_perf_b ... out_perf_i).
# The release v0.5.1 is the last round, 0.5.1-i: RELEASE=1 EMU_BIN=... LAUNCHER_BIN=... make_perf_app.sh 0.5.1 -> out_perf/.
# The launcher, mod engine and licences are taken from the base unchanged. The emulator too, unless
# EMU_BIN=<built shadps4> is given (0.5.1-f: guest yield, process priority and guest thread QoS changes);
# either way the emulator binary is re-signed with the get-task-allow entitlement (0.5.1-c).
set -euo pipefail
# RELEASE=1: every binary must be current with its source tree before it is packaged. 0.5.1-i carried an x86
# libbbgpu from before the last source changes because only the arm64 side had been rebuilt.
if [ "${RELEASE:-0}" = 1 ]; then
    P=~/fifa_metal/fifa16_mac_port/out
    fresh() { ninja -C "$1" ${2:-} 2>&1 | tail -1 | grep -q "no work to do" || { echo "RELEASE=1: $1 was not up to date; it has been rebuilt, test it and package again"; exit 1; }; }
    fresh "$P/gpu-arm64" bbgpu; fresh "$P/gpu" bbgpu; 
    if [ -n "${EMU_BIN:-}" ]; then   # the emulator build always re-runs an external step, so compare the binary instead
        h0=$(shasum "$EMU_BIN" | cut -c1-40); ninja -C "$(dirname "$EMU_BIN")" > /dev/null 2>&1 || { echo "RELEASE=1: emulator build failed"; exit 1; }
        [ "$h0" = "$(shasum "$EMU_BIN" | cut -c1-40)" ] || { echo "RELEASE=1: the emulator was not up to date; it has been rebuilt, test it and package again"; exit 1; }
    fi
    for h in bbgpu-host bbgpu-host-macos26 bbgpu-host-macos27; do
        if [ "$P/gpu-arm64/libbbgpu.dylib" -nt "$P/$h" ]; then echo "RELEASE=1: $h is older than libbbgpu, run build_host.sh"; exit 1; fi
    done
fi
ver=${1:?version}; BASE=${2:-$HOME/fifa_metal/app/out_host26/F16.app}; OUTDIR=${OUT:-$HOME/fifa_metal/app/out_perf}
B=~/fifa_metal/fifa16_mac_port; OUT=$OUTDIR; rm -rf "$OUT"; mkdir -p "$OUT"
cp -R "$BASE" "$OUT/F16.app"; APP="$OUT/F16.app"; RES="$APP/Contents/Resources"
HM="$APP/Contents/Helpers/F16 GPU.app/Contents/MacOS"; EMU="$RES/emulator"
cp "$B/out/bbgpu-host" "$B/out/bbgpu-host-macos26" "$B/out/bbgpu-host-macos27" "$B/out/gpu-arm64/libbbgpu.dylib" "$B/out/gpu-arm64/libbbhost.dylib" "$HM/"
cp "$B/out/gpu/libbbgpu.dylib" "$EMU/libbbgpu.dylib"     # the in-process fallback (x86-64)
cp "$HOME/fifa_metal/app/run.sh" "$RES/run.sh"; chmod +x "$RES/run.sh"
# 0.5.1-i: nothing made from the game is bundled. The shader cache and the start-up patch record are built on the
# user's Mac from their own game files and kept in their savegame folder (run.sh place_caches). 0.5.1 to 0.5.1-h
# carried Resources/shader_seed (the game's shaders, translated) and, from -g, Resources/patch_seed.
rm -rf "$RES/shader_seed" "$RES/patch_seed"
otool -l "$HM/libbbhost.dylib" | grep -q '@loader_path' || install_name_tool -add_rpath @loader_path "$HM/libbbhost.dylib"
for f in "$HM/bbgpu-host" "$HM/bbgpu-host-macos26" "$HM/bbgpu-host-macos27" "$HM/libbbhost.dylib" "$HM/libbbgpu.dylib" "$EMU/libbbgpu.dylib"; do
    for rp in $(otool -l "$f" | awk '/LC_RPATH/{getline; getline; print $2}'); do
        case "$rp" in @*) ;; *) install_name_tool -delete_rpath "$rp" "$f" ;; esac
    done
    case "$f" in *.dylib) otool -l "$f" | grep -q '@loader_path' || install_name_tool -add_rpath @loader_path "$f" ;;
                *) otool -l "$f" | grep -q '@executable_path' || install_name_tool -add_rpath @executable_path "$f"; chmod +x "$f" ;; esac
done
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $ver" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $ver" "$APP/Contents/Info.plist" 2>/dev/null || true
# SOURCES.txt names the commit each part was built from. A repository with uncommitted changes is marked, and the
# closing line then says the bundle is a local build: the listed commits alone do not rebuild it, so it must not be
# published (GPL: the corresponding source has to be available). RELEASE=1 refuses to package in that state and
# also wants the tag v<version> on each commit.
src_line() { # <label> <url> <repo dir>
    local head state=""
    head=$(git -C "$3" rev-parse HEAD 2>/dev/null || echo unknown)
    if [ -n "$(git -C "$3" status --porcelain 2>/dev/null)" ]; then state="  + uncommitted changes"
    elif [ "${RELEASE:-0}" = 1 ] && ! git -C "$3" tag --points-at HEAD | grep -qx "v$ver"; then echo "RELEASE=1: $3 has no tag v$ver on HEAD" >&2; exit 1; fi
    printf '%-50s %s  %s%s\n' "$1" "$2" "$head" "$state"
}
{ echo "F16.app $ver - corresponding source"; echo
  src_line "fifa16_mac_port (libbbgpu, bbgpu-host*, libbbhost)" https://github.com/VladZ97/fifa16_mac_port ~/fifa_metal/bloodborne_mac_port
  src_line "shadps4-fifa (emulator)" https://github.com/VladZ97/shadps4-fifa ~/fifa_metal/shadps4-metal
  src_line "fifa16-shadps4-tools (launcher, run.sh, scripts)" https://github.com/VladZ97/fifa16-shadps4-tools ~/fifa16-shadps4-tools
  src_line "fifa16-mods (fifamod engine)" https://github.com/VladZ97/fifa16-mods ~/FIFA16Mods
  echo; } > "$RES/SOURCES.txt"
if grep -q "uncommitted changes" "$RES/SOURCES.txt"; then
    [ "${RELEASE:-0}" = 1 ] && { echo "RELEASE=1: uncommitted changes, see $RES/SOURCES.txt"; exit 1; }
    echo "LOCAL BUILD, not for publication: built from the commits above plus uncommitted changes. Third-party versions: see Licenses/README.md." >> "$RES/SOURCES.txt"
    echo "sources: LOCAL BUILD (uncommitted changes); commit, tag v$ver and package with RELEASE=1 before publishing"
else
    echo "Each repository carries the tag v$ver at the commit above. Third-party versions: see Licenses/README.md." >> "$RES/SOURCES.txt"
    echo "sources: all four repositories clean"
fi
# 0.5.1-c: the host changes the game's page protection through the emulator's task port (task_for_pid,
# host_runtime.c host_protect_direct_init): the emulator binary carries com.apple.security.get-task-allow.
# Without it the host falls back to the relay through the game's protect thread (0.5.1-b behaviour).
cat > "$OUT/get-task-allow.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.get-task-allow</key><true/></dict></plist>
PLIST
if [ -n "${EMU_BIN:-}" ]; then
    cp "$EMU_BIN" "$EMU/shadps4"; chmod 755 "$EMU/shadps4"
    for rp in $(otool -l "$EMU/shadps4" | awk '/LC_RPATH/{getline; getline; print $2}'); do
        case "$rp" in @*) ;; *) install_name_tool -delete_rpath "$rp" "$EMU/shadps4" ;; esac
    done
    otool -l "$EMU/shadps4" | grep -q '@executable_path' || install_name_tool -add_rpath @executable_path "$EMU/shadps4"
    echo "emulator: $(basename "$EMU_BIN") from $(dirname "$EMU_BIN") ($(stat -f %z "$EMU/shadps4") bytes)"
fi
# LAUNCHER_BIN=<built launcher binary> replaces the base bundle's launcher (0.5.1-g: the 120 Hz toggle).
if [ -n "${LAUNCHER_BIN:-}" ]; then cp "$LAUNCHER_BIN" "$APP/Contents/MacOS/F16"; chmod 755 "$APP/Contents/MacOS/F16"; echo "launcher: $(stat -f %z "$APP/Contents/MacOS/F16") bytes from $LAUNCHER_BIN"; fi
# Publishable-bundle check: no shader/pipeline/patch caches, no game files, no build-machine paths in text files.
dirty=$(find "$APP" -type f \( -name "*.spv" -o -name "*.metal" -o -name "*.binaryarchive" -o -name "*.spc" -o -name "*.meta" -o -name "*.key" \
    -o -name "*.rx3" -o -name "*.big" -o -name "*.dds" -o -name "*.sfo" -o -name "*.pkg" -o -name "eboot.bin" -o -name "*.sprx" -o -name "*.prx" \
    -o -name "*.at9" -o -name "*.sbk" -o -name "*.db" -o -name "keys.json" \) | head -5)
[ -z "$dirty" ] || { echo "game-derived or game files in the bundle:"; echo "$dirty"; exit 1; }
if grep -rIl "/Users/" "$APP" 2>/dev/null | head -3 | grep -q .; then echo "build-machine path in a bundle text file:"; grep -rIl "/Users/" "$APP" | head -3; exit 1; fi
echo "bundle check: no caches, no game files"
# 0.5.1-i: the binaries carry the build machine's home folder in assert messages and debug symbols; replaced by a
# neutral path of the same length before signing (scrub_build_paths.py), and the packaging stops if any is left.
python3 "$(dirname "$0")/scrub_build_paths.py" "$APP" || exit 1
codesign --force --sign - --entitlements "$OUT/get-task-allow.plist" "$EMU/shadps4"
rm -rf "$APP/Contents/Helpers/F16 GPU.app/Contents/_CodeSignature"
xattr -cr "$APP" 2>/dev/null || true; find "$APP" -name "._*" -delete
codesign --force --deep -s - "$APP"; codesign --verify --deep --strict "$APP" && echo "signature ok"
codesign -d --entitlements - "$EMU/shadps4" 2>&1 | grep -q get-task-allow && echo "emulator: get-task-allow kept" || { echo "emulator lost get-task-allow"; exit 1; }
for f in "$HM/bbgpu-host" "$HM/bbgpu-host-macos26" "$HM/bbgpu-host-macos27" "$HM/libbbhost.dylib" "$HM/libbbgpu.dylib" "$EMU/libbbgpu.dylib"; do
    otool -l "$f" | awk '/LC_RPATH/{getline; getline; print $2}' | grep -v '^@' && { echo "outside rpath in $f"; exit 1; }
done
"$HM/bbgpu-host-macos26" 2>&1 | head -2 || true
(cd "$OUT" && rm -f "F16-macOS-$ver.zip" && ditto -c -k --norsrc --keepParent "F16.app" "F16-macOS-$ver.zip" && du -sh "F16-macOS-$ver.zip" | cut -f1)
