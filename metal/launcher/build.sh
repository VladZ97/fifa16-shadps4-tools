#!/usr/bin/env bash
# Builds FIFA 16.app here (~/fifa_metal/launcher), the same way the Bloodborne port builds its
# launcher (scripts/macos/build_launcher.sh + make_app.sh): plain swiftc over Model/ and App/,
# an ad-hoc signed bundle, the icon and header art made from the game's own sce_sys artwork.
#
#   bash build.sh          # build FIFA 16.app
#   bash build.sh --test   # also build and run the model tests (Tests/main.swift)
#
# Reads only: ~/fifa_metal/run.sh (for the game path) and the game's sce_sys/icon0.png, pic1.png.
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
version=1.0
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
    <key>NSHumanReadableCopyright</key><string>Launcher for ~/fifa_metal/run.sh (shadPS4 Metal hybrid build).</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.sports-games</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
install -m755 "$out/FIFA16Launcher" "$app/Contents/MacOS/FIFA 16"

# Game artwork (read-only): the eboot path run.sh uses, its sce_sys folder.
game=$(grep -E '^GAME=' "$HOME/fifa_metal/run.sh" | sed -E 's/^GAME="\$\{SIDE_GAME:-([^}]*)\}".*/\1/')
sce=$(dirname "$game")/sce_sys
if [[ -f $sce/icon0.png ]]; then
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
    echo "No $sce/icon0.png (game drive not mounted?): the app has no icon. Run build.sh again later."
fi
if [[ -f $sce/pic1.png ]]; then
    sips -s format jpeg -s formatOptions 80 --resampleWidth 1800 "$sce/pic1.png" --out "$app/Contents/Resources/banner.jpg" >/dev/null
fi
codesign --force --sign - "$app" >/dev/null 2>&1 || codesign --force --sign - "$app/Contents/MacOS/FIFA 16"
touch "$app"
echo "Built $app"
