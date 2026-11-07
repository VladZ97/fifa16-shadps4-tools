#!/bin/bash
# fifa-hybrid: builds bbgpu-host (native arm64) against out/gpu-arm64/libbbgpu.dylib.
set -euo pipefail
cd ~/fifa_metal/fifa16_mac_port
ROOT=$PWD; ARM64_PREFIX=$ROOT/deps/arm64
host_cc=(/usr/bin/clang -arch arm64 -mmacosx-version-min=15.0 -std=c11 -O2 -g -Wall -Wextra -Werror
    -I. host/main.c host/host_runtime.c -Lout/gpu-arm64 -lbbgpu -Wl,-rpath,"$ROOT/out/gpu-arm64"
    -Wl,-rpath,"$ARM64_PREFIX/lib" -framework CoreFoundation)
# The plain host (macOS < 27) carries the SDK 12.0 stamp too (see build_host26.sh): without the xzone
# pointer range its mmap hints should get both ranges on 26 directly; -macos27 keeps its own build.
"${host_cc[@]}" -Wl,-platform_version,macos,15.0,12.0 -o out/bbgpu-host
"${host_cc[@]}" host/guest_reservation_low.s host/guest_reservation.s \
    -Wl,-segaddr,__GUESTRSV,0x7000000000 -Wl,-segprot,__GUESTRSV,---,--- \
    -Wl,-segaddr,__GUESTLOW,0x400000000 -Wl,-segprot,__GUESTLOW,---,--- \
    -o out/bbgpu-host-macos27
bash ~/fifa_metal/build_host26.sh   # macOS 26 host: stub + libbbhost.dylib (renderer objects + host code)
echo "Built out/bbgpu-host, out/bbgpu-host-macos27, out/bbgpu-host-macos26 (+ out/gpu-arm64/libbbhost.dylib)"
