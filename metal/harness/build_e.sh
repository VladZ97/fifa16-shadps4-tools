#!/bin/bash
# build_e.sh [x86]: arm64 library + hosts (+ x86 library when asked), under the build lock; refreshes the harness host bundle.
S=${S:-${TMPDIR:-/tmp}/fifa_harness}; mkdir -p "$S"   # scratch folder for logs and intermediate files
while pgrep -x shadps4 >/dev/null; do sleep 5; done
touch $S/build.lock
cd ~/fifa_metal/bloodborne_mac_port || exit 1
nice -n 19 ninja -C out/gpu-arm64 -j4 bbgpu 2>&1 | grep -E "error|FAILED|Linking|ninja: (no work|build stopped)" | head -30
rc=${PIPESTATUS[0]}
if [ $rc -eq 0 ]; then bash ~/fifa_metal/build_host.sh 2>&1 | tail -2; rc=$?; fi
if [ $rc -eq 0 ] && [ "$1" = x86 ]; then bash build_macos.sh --gpu-only 2>&1 | grep -E "error|FAILED|Built|Linking" | tail -5; rc=${PIPESTATUS[0]}; fi
if [ $rc -eq 0 ]; then
  HM="$HOME/fifa_metal/host_app/F16 GPU.app/Contents/MacOS"
  for f in bbgpu-host bbgpu-host-macos26 bbgpu-host-macos27; do cp out/$f "$HM/$f.new" && mv -f "$HM/$f.new" "$HM/$f"; done
  for f in libbbgpu.dylib libbbhost.dylib; do [ -e "$HM/$f" ] && { cp out/gpu-arm64/$f "$HM/$f.new" && mv -f "$HM/$f.new" "$HM/$f"; }; done
  codesign --force --deep --sign - "$HOME/fifa_metal/host_app/F16 GPU.app" 2>&1 | tail -1
fi
rm -f $S/build.lock; echo "build exit $rc $(date +%H:%M:%S)"
