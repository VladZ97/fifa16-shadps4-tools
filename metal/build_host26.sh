#!/bin/bash
# fifa-hybrid: the macOS 26 GPU host. macOS 26's dyld fails every flat-namespace lookup in a process whose
# executable has a pinned zero-fill segment, so this host has none: libbbhost.dylib is the renderer's own
# object files (out/gpu-arm64, exactly the objects of libbbgpu.dylib, same link command) linked together with
# host/main.c and host/host_runtime.c, the runtime_* callbacks resolved at link time; bbgpu-host-macos26 is a
# stub executable carrying only the two pinned ranges (host/stub_main.c). Run after build_gpu_arm64.sh.
set -euo pipefail
cd ~/fifa_metal/bloodborne_mac_port
ROOT=$PWD; G=out/gpu-arm64; OBJ=$G/host26; mkdir -p "$OBJ"
CC=(/usr/bin/clang -arch arm64 -mmacosx-version-min=15.0 -std=c11 -O2 -g -Wall -Wextra -Werror -I. -DBBGPU_HOST_MAIN=bbgpu_host_main)
"${CC[@]}" -c host/main.c -o "$OBJ/main.o"
"${CC[@]}" -c host/host_runtime.c -o "$OBJ/host_runtime.o"
ninja -C "$G" -n bbgpu 2>&1 | grep -q "clang" && { echo "out/gpu-arm64 objects are not current: run scripts/macos/build_gpu_arm64.sh first"; exit 1; }
link=$(ninja -C "$G" -t commands bbgpu | tail -1)
link=${link#: && }; link=${link% && :}
link=$(echo "$link" | sed -E 's/-Wl,-U,_[A-Za-z0-9_]+ //g; s#-o libbbgpu\.dylib#-o libbbhost.dylib#; s#-install_name @rpath/libbbgpu\.dylib#-install_name @rpath/libbbhost.dylib#')
(cd "$G" && eval "$link host26/main.o host26/host_runtime.o -framework CoreFoundation")
nm -u "$G/libbbhost.dylib" | grep -q "_runtime_" && { echo "libbbhost.dylib still imports runtime_* symbols"; exit 1; }
# SDK stamp 12.0 (-platform_version, no old SDK needed): libmalloc picks its allocator by the main
# executable's linked SDK; from 13 on it is xzone, which on macOS 26 must place a 24 GiB "pointer range"
# below 64 GiB at process start and aborts the process when the pinned low range leaves no room
# ("BUG IN LIBMALLOC: pointer range initial reservation failed"). With the stamp the classic allocator
# runs: no such reservation at all (walk on 27: 0 regions in either range), so the full low range is back.
/usr/bin/clang -arch arm64 -mmacosx-version-min=15.0 -std=c11 -O2 -g -Wall -Wextra -Werror \
    -Wl,-platform_version,macos,15.0,12.0 \
    host/stub_main.c host/guest_reservation_low.s host/guest_reservation.s -L"$G" -lbbhost -Wl,-rpath,"$ROOT/$G" \
    -Wl,-segaddr,__GUESTRSV,0x7000000000 -Wl,-segprot,__GUESTRSV,---,--- \
    -Wl,-segaddr,__GUESTLOW,0x400000000 -Wl,-segprot,__GUESTLOW,---,--- \
    -o out/bbgpu-host-macos26
echo "Built out/bbgpu-host-macos26 + $G/libbbhost.dylib ($(du -h "$G/libbbhost.dylib" | cut -f1))"
