#!/usr/bin/env bash
# Builds the launcher executable and the bare FIFA 16.app skeleton here (~/fifa_metal/launcher),
# the same way the Bloodborne port builds its launcher: plain swiftc over Model/ and App/, an
# ad-hoc signed bundle, the icon and header art made from the game's own sce_sys artwork.
# The payload (emulator, GPU host app, run.sh, settings, fifamod) is added afterwards by
# make_app.sh, which also signs the finished bundle.
#
#   bash build.sh          # build FIFA 16.app (skeleton)
#   bash build.sh --test   # also build and run the model tests (Tests/main.swift)
#
# Artwork: GAME_ART_DIR=<folder with icon0.png and pic1.png> (a game's sce_sys folder);
# without it the app has no icon, which is not an error.
set -euo pipefail
cd -- "$(dirname -- "$0")"
here=$PWD
out=$here/out
app=$here/FIFA\ 16.app
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
    <key>CFBundleName</key><string>FIFA 16</string>
    <key>CFBundleDisplayName</key><string>FIFA 16</string>
    <key>CFBundleIdentifier</key><string>local.fifa-metal.fifa16-launcher</string>
    <key>CFBundleExecutable</key><string>FIFA 16</string>
    <key>CFBundleIconFile</key><string>FIFA16</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>NSHumanReadableCopyright</key><string>FIFA 16 (PS4) on Apple Silicon: shadPS4 with the native Metal renderer, self-contained.</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.sports-games</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
install -m755 "$out/FIFA16Launcher" "$app/Contents/MacOS/FIFA 16"

# Game artwork (read-only): GAME_ART_DIR, else the game folder from the launcher's own
# settings.json if there is one. Missing art only means no icon.
sce=${GAME_ART_DIR:-}
if [[ -z $sce ]]; then
    settings="$HOME/Library/Application Support/FIFA 16/settings.json"
    if [[ -f $settings ]]; then
        game=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("gameDir",""))' "$settings" 2>/dev/null || true)
        [[ -n $game ]] && sce=$game/sce_sys
    fi
fi
if [[ -n $sce && -f $sce/icon0.png ]]; then
    tmp=$(mktemp -d)
    set_dir=$tmp/FIFA16.iconset
    mkdir -p "$set_dir"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$sce/icon0.png" --out "$set_dir/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z $double $double "$sce/icon0.png" --out "$set_dir/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$set_dir" -o "$app/Contents/Resources/FIFA16.icns"
    rm -rf "$tmp"
else
    echo "No game artwork (set GAME_ART_DIR=<sce_sys folder>): the app has no icon."
fi
if [[ -n $sce && -f $sce/pic1.png ]]; then
    sips -s format jpeg -s formatOptions 80 --resampleWidth 1800 "$sce/pic1.png" --out "$app/Contents/Resources/banner.jpg" >/dev/null
fi
codesign --force --sign - "$app" >/dev/null 2>&1 || codesign --force --sign - "$app/Contents/MacOS/FIFA 16"
touch "$app"
echo "Built $app"
