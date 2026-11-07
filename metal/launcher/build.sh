#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Builds the launcher executable and the bare F16.app skeleton here (~/fifa_metal/launcher),
# the same way the Bloodborne port builds its launcher: plain swiftc over Model/ and App/, an
# ad-hoc signed bundle, the app's own icon (art/icon.png).
# The payload (emulator, GPU host app, run.sh, settings, fifamod) is added afterwards by
# make_app.sh, which also signs the finished bundle.
#
#   bash build.sh          # build F16.app (skeleton)
#   bash build.sh --test   # also build and run the model tests (Tests/main.swift)
#
# Icon: art/icon.png (drawn by art/draw_icon.swift); no game artwork in the bundle.
# without it the app has no icon, which is not an error.
set -euo pipefail
cd -- "$(dirname -- "$0")"
here=$PWD
out=$here/out
app=$here/F16.app
mkdir -p "$out"
target=(-target arm64-apple-macos15.0)
model=(Model/*.swift)

if [[ ${1:-} == --test ]]; then
    swiftc "${target[@]}" "${model[@]}" Tests/main.swift -o "$out/launcher-tests"
    "$out/launcher-tests"
fi

swiftc -O "${target[@]}" "${model[@]}" App/*.swift -o "$out/FIFA16Launcher"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
version=2.0
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>F16</string>
    <key>CFBundleDisplayName</key><string>F16</string>
    <key>CFBundleIdentifier</key><string>local.fifa-metal.fifa16-launcher</string>
    <key>CFBundleExecutable</key><string>F16</string>
    <key>CFBundleIconFile</key><string>FIFA16</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>NSHumanReadableCopyright</key><string>F16: the PS4 football game of 2015 on Apple Silicon, shadPS4 with the native Metal renderer, self-contained. Unofficial, no affiliation with the game's publisher.</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.sports-games</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
install -m755 "$out/FIFA16Launcher" "$app/Contents/MacOS/F16"

# Icon: the app's own drawing (art/draw_icon.swift -> art/icon.png, checked in). No game artwork is
# used anywhere in the bundle; the launcher shows the game's own header art at runtime, read from
# the game folder the user chose.
if [[ -f art/icon.png ]]; then
    tmp=$(mktemp -d)
    set_dir=$tmp/FIFA16.iconset
    mkdir -p "$set_dir"
    for size in 16 32 128 256 512; do
        sips -z $size $size art/icon.png --out "$set_dir/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z $double $double art/icon.png --out "$set_dir/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$set_dir" -o "$app/Contents/Resources/FIFA16.icns"
    rm -rf "$tmp"
else
    echo "art/icon.png missing (swift art/draw_icon.swift art/icon.png): the app has no icon."
fi
codesign --force --sign - "$app" >/dev/null 2>&1 || codesign --force --sign - "$app/Contents/MacOS/F16"
touch "$app"
echo "Built $app"
