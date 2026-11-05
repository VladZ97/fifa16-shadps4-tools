#!/bin/bash
# Switch the FIFA 16 /download0 overlay between the FIP patch and the pre-patch backup.
# usage: fifa_overlay.sh fip | prefip | nolua | nodb | nosle | stockcrowd | stockstadium | stockplayer | nogentex | nogeneral | stocksmall | stockgoalnet | stockaccessory | stockplayer2 | stockball | stockcorner | stockdigital | stockwipe | stockfancards | stockoutro | ballA | ballB | status
D="$HOME/Library/Application Support/shadPS4/download"
case "${1:-status}" in
  fip)    rm -f "$D/CUSA02138"; ln -s "/Volumes/SanDiskSSD/Manual Install" "$D/CUSA02138"; echo "overlay -> FIP patch";;
  prefip) rm -f "$D/CUSA02138"; ln -s "$D/CUSA02138.pre-fip" "$D/CUSA02138"; echo "overlay -> pre-patch backup";;
  nolua)  rm -f "$D/CUSA02138"; ln -s "$D/CUSA02138.nolua" "$D/CUSA02138"; echo "overlay -> FIP without its Lua scripts";;
  nosle)  rm -f "$D/CUSA02138"; ln -s "$D/CUSA02138.nosle" "$D/CUSA02138"; echo "overlay -> FIP with stock sideline scripts (sle.lua, batchsle.lua)";;
  stockcrowd|stockstadium|stockplayer|nogentex|nogeneral|stocksmall|stockgoalnet|stockaccessory|stockplayer2|stockball|stockcorner|stockdigital|stockwipe|stockfancards|stockoutro|ballA|ballB) rm -f "$D/CUSA02138"; ln -s "$D/CUSA02138.$1" "$D/CUSA02138"; echo "overlay -> FIP with stock $1";;
  nodb)   rm -f "$D/CUSA02138"; ln -s "$D/CUSA02138.nodb" "$D/CUSA02138"; echo "overlay -> FIP without its database/compdata";;
  *)      echo "CUSA02138 -> $(readlink "$D/CUSA02138" || echo '(directory)')";;
esac
