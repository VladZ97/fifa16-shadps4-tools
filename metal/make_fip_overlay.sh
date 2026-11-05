#!/bin/zsh
# make_fip_overlay.sh <name> <theme>: builds ~/fifa_perf/overlay/CUSA02138.<name> = the full FIP patch
# (symlinks into /Volumes/SanDiskSSD/Manual Install) with the FIP theme <theme> laid over it and the
# lean player.lua / crowd.lua from the leanlua overlay, without changing the Manual Install itself.
set -e
NAME=$1; THEME=$2
M="/Volumes/SanDiskSSD/Manual Install"
LEAN=~/fifa_perf/overlay/CUSA02138.leanlua
O=~/fifa_perf/overlay/CUSA02138.$NAME
rm -rf "$O"; mkdir -p "$O"
# top level: symlink everything from the patch
for e in "$M"/* "$M"/.[!.]*; do [ -e "$e" ] || continue; b=$(basename "$e"); [[ "$b" == ._* ]] && continue; ln -s "$e" "$O/$b"; done
# materialise(dir): turn a symlinked dir inside the overlay into a real dir of per-entry symlinks
materialise() { local rel=$1 p="$O/$rel"
  if [ -L "$p" ]; then local target=$(readlink "$p"); rm "$p"; mkdir -p "$p"
    for e in "$target"/* "$target"/.[!.]*; do [ -e "$e" ] || continue; local b=$(basename "$e"); [[ "$b" == ._* ]] && continue; ln -s "$e" "$p/$b"; done
  elif [ ! -d "$p" ]; then mkdir -p "$p"; fi; }
# place(file-in-source, rel): materialise parents, then copy the file in
place() { local src=$1 rel=$2; local d=$(dirname "$rel"); local acc=""
  for part in ${(s:/:)d}; do acc="${acc:+$acc/}$part"; materialise "$acc"
    if [ -L "$O/$acc" ]; then echo "refusing: $O/$acc is still a symlink"; exit 1; fi; done
  if [ -L "$O/$rel" ]; then rm "$O/$rel"; elif [ -e "$O/$rel" ]; then rm "$O/$rel"; fi
  cp "$src" "$O/$rel"; }
# the theme (manager "Install theme" = copy over the root, skipping preview.png)
n=0
while IFS= read -r f; do rel=${f#"$M/fip/theme/$THEME/"}; [ "$rel" = preview.png ] && continue; place "$f" "$rel"; n=$((n+1)); done < <(find "$M/fip/theme/$THEME" -type f -not -name '._*')
echo "theme files placed: $n"
# the lean scripts and the intro-skip nav from the leanlua overlay
place "$LEAN/data/fifarna/lua/assets/player.lua" data/fifarna/lua/assets/player.lua
place "$LEAN/data/fifarna/lua/assets/crowd.lua" data/fifarna/lua/assets/crowd.lua
place "$LEAN/data/ui/nav/bootcommonflow.nav" data/ui/nav/bootcommonflow.nav
# the patch's own backups must not shadow anything (they are symlinked, harmless) - done
echo "overlay $O ready"; find "$O" -type f | wc -l
