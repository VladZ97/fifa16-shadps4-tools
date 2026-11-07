---
name: fifa16-app-macos26-host
description: "FIFA 16.app GPU host on macOS 26 - libmalloc xzone pointer range below 64 GiB; SDK 12 stamp on the host avoids it (v0.4.5), in-process fallback, how to test without breaking the game"
metadata:
  node_type: memory
  type: project
  originSessionId: dbbed053-17e5-4d95-b585-d31d29a90051
  modified: 2026-11-06T21:05:27.672Z
---

macOS < 27 runs the plain `bbgpu-host`. On macOS 26 the xzone libmalloc places a 24 GiB "pointer range" at a random
spot BELOW 64 GiB before main and aborts the process when it cannot ("BUG IN LIBMALLOC: pointer range initial
reservation failed", SIGTRAP in __malloc_init; crash reports from the user's 26.3 Mac, 2026-11-07). The game's low
range 0x400000000-0xfa0000000 sits exactly there: an mmap hint loses to the block, and ANY sizeable pinned segment
there (46.5 or 20 GiB) kills the process; only ~1 GiB pins survive. 27's libmalloc uses 0x7xxxxxxxxx instead.
Fix (v0.4.5): libmalloc picks the allocator by the main executable's linked SDK - stamp the host with
`-Wl,-platform_version,macos,15.0,12.0` (no old SDK needed; sdk 13/14 still xzone) and no pointer range exists at
all. Plain host + `bbgpu-host-macos26` (stub executable with pinned segments + `libbbhost.dylib` = renderer objects
relinked with the host code, `~/fifa_metal/build_host26.sh`; pinned segments in an executable with code break 26's
flat-namespace lookups) both carry the stamp; the plain host execv()s into the stub if its hints fail. run.sh falls
back to SHAD_BBGPU_SPLIT=0 (in-process, ~30 fps on that Mac) if no host starts. Package:
`app/make_host26_app.sh <ver> [base] [--no-macos27]`. v0.4.5 CONFIRMED on the 26 Mac (native host, 60 fps). v0.4.6 adds the saves fix (fs.cpp update overlay only for
/app0), BB_GPU_USER_DIR/BB_CAPTURE_DIR isolation, own-process-only stop in run.sh, no Save Migration prompt
(user_manager.cpp); user confirmed saves work. Probe kit
FIFA16-host26-kit on the SSD (stub11/stub12 = stamped layouts).

**Why:** the user's rule is "do not break the game": emulator, `-macos27` host and libbbgpu.dylib must stay
byte-identical; v0.3.1 was blamed for broken graphics though the host change was not the cause.
**How to apply:** change only the plain host / add files; verify with `work26/compare_apps.py` that nothing else
differs; test the re-exec path on this Mac by packaging with `--no-macos27` and running the work26 harness
(`HOST_PROC_NAME=bbgpu-host-macos26`). The harness's state classifier calls modded matches STALL; judge by
screenshots and FSTAT. First signal on a 26 Mac: run `.../FIFA 16 GPU.app/Contents/MacOS/bbgpu-host-macos26` by hand
(expect "pid ..., native arm64" then "not started by bb-probe"). Related: [[fifa16-app-mods-page]].
