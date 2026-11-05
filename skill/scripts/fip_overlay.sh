#!/bin/zsh
# Link the shadPS4 download overlay for a title to a PC patch folder and stage root ini files.
# usage: fip_overlay.sh <TITLEID> "<patch folder>" "<game folder>"   (game folder = .../<TITLEID>)
set -e
TITLE="$1"; PATCH="$2"; GAME="$3"
[ -n "$TITLE" ] && [ -d "$PATCH" ] && [ -d "$GAME" ] || { echo "usage: $0 <TITLEID> <patch folder> <game folder>"; exit 1; }
DL="$HOME/Library/Application Support/shadPS4/download"
mkdir -p "$DL"; cd "$DL"
if [ -e "$TITLE" ] && [ ! -L "$TITLE" ]; then mv "$TITLE" "$TITLE.pre-patch-$(date +%Y%m%d%H%M)"; echo "backed up existing overlay"; fi
ln -sfn "$PATCH" "$TITLE"; echo "/download0 -> $PATCH"
MODS="$(dirname "$GAME")/$TITLE-mods"; mkdir -p "$MODS"
n=0; for f in "$PATCH"/*.ini; do [ -f "$f" ] && cp "$f" "$MODS/" && n=$((n+1)); done
echo "$n root ini files staged in $MODS (served as /app0/*.ini)"
