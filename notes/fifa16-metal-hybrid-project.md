---
name: fifa16-metal-hybrid-project
description: Side project (started 2026-10-29) running FIFA 16 through the Bloodborne mac port's native Metal GPU library inside shadPS4; first light reached the same day; locations, design, how to build and run
metadata:
  type: project
---

Started 2026-10-29 after the user saw github.com/Wooloomooloo2/bloodborne_mac_port ("can we also do the same?").
Everything lives in ~/fifa_metal (clone of the port, PLAN.md, worktree ~/fifa_metal/shadps4-metal on branch
`metal-hybrid` off playable-60-v1 with externals symlinked read-only to ~/fifa_perf/shadps4/externals).
The daily build (Custom-perf, tag playable-60-v1.4) and Custom-flipfix stay untouched.

Design: shadPS4 stays FIFA's runtime; the port's gpu/ (shadPS4 video core vendored at upstream b4e7ae7 +
native Metal renderer + MetalFX/FSR) is linked as libbbgpu.dylib. Bridge = ~13 `runtime_*` C functions
(memory region/clamp/is_mapped/write_backing/gpu_protect/set_gpu_hooks, process time/tsc, errno,
thread blocked) + linker fallback to `bbgpu_resolve` for GnmDriver/VideoOut NIDs + an access-violation
handler calling `bbgpu_handle_fault` + memory hooks where memory.cpp calls rasterizer->Map/Unmap/Invalidate.

**Why:** open play is already 60; the gain is the crowd-heavy views (GPU 19-26 ms at 1080p -> game locks
to 30) via upscaling, and native encoding without pass splits.

**Status 2026-10-29 16:00:** first light. FIFA renders through the Metal library in-process under Rosetta
(tunnel intro 60 FPS/16.7 ms). Needed: library fork branch `fifa-hybrid` (external Metal layer, wider
GetUsableRegions, bbgpu_memory_* entry points that also feed BbArenaRuns + Refresh), `BB_ARENA_LAYOUT=runs`
(FIFA's GPU memory sits at 0x2xxxxxxxx, outside the Bloodborne arena base 0x7000000000), shadPS4 skips its
ImGui layer when the bridge is on, region queries must accept null out-pointers.

**How to apply:** rebuild library: `cmake --build ~/fifa_metal/bloodborne_mac_port/out/gpu` (the initial
bootstrap_deps.sh/build_macos.sh needed the user to run them: permission classifier blocks external scripts).
Rebuild shadPS4: `cmake --build ~/fifa_metal/shadps4-metal/build --parallel 8` then `bash ~/fifa_metal/install.sh`.
Run: `bash ~/fifa_metal/run.sh start|play` (SHAD_BBGPU=0 for the old renderer in the same binary); autotest
target `metal`. Launcher version Custom-metal. Two SDL copies in the process (objc duplicate-class warnings). See [[fifa16-shadps4-mac-setup]].

**Status 2026-10-29 22:00:** crowd seat colours fixed (a5nz 63611/63611). Cause: FindRenderTarget queued
the on-demand readback before UpdateImage, and RefreshImage's refresh-resolve downloaded the image before
the draw, so the CPU read pre-draw contents. Fix: QueueReadback after UpdateImage (also in FindTexture
storage path) + ondemand_seq ordering in DownloadImagesForCpuRead. User watched the result and said it
looks good; the judge still flags side_select as darker (~0.4x vs perf refs) — unconfirmed whether it
matters. Still open: pink players / stadium-entry hang recheck, debug-code cleanup ([DMAP], [PROBE], RBQ).
**2026-10-29 22:02 match check (run 20261029_215911, VIS_STATES="loading_drill in_match"):** menus OK (the
kit_select_ready "VISUAL_BAD" was a judge false positive: the screen was still the team READY view).
Stadium entry still breaks: the Camp Nou flyover has blown-out cyan/white/blue city buildings, then the picture
freezes for 64 s in loading_drill (STALL) while the game threads keep logging. The user saw a match render
"very bad and very very stuttery". Next: find the flyover's overbright pass (HDR/float format or exposure)
and why presents stop during loading_drill.

2026-10-29 22:25: stadium textures root cause = GPU BC3 compression writing via RGBA32Uint storage view (Metal can't).
Implemented "block shadow" image (see ~/fifa_metal/PLAN.md, toggle BB_NO_BLOCK_SHADOW=1). First run to
loading_drill: 0 "Impacting Interactivity". User asked to stop here; visuals/match/FPS not yet verified.
2026-10-29 23:01: with block shadow, metal reached the walkout cutscene, then the whole Mac hung (WindowServer
watchdog) ~1 min later. Don't rerun in-match drives without a GPU-hog guard and the user's OK.
2026-10-30: a match is reachable (MATCH_OK, ~39 fps, BB_GPU_WATCHDOG_MS=2000 always). GPU-written BC1 images
(BB_DUMP_GPUBC=1) are player FACE textures, and all their mips decode clean. So the remaining rainbow-noise on SOME
players is not GPU BC1 face mips. BlockDim() is pitch>>2, so a BC dst overlapping a uint src of the same block size
goes through ExpandImage (CopyImage covers mip 0 only), not the BCSEED path. On macOS, prune runs with
`tail -r | tail -n +3` (head -n -N does not work there).

## Kit noise status (2026-10-30, FIXED)
- Root cause: the env-probe cube (R11G11B10 256^2, 5 mips, 6 faces) is rendered once per face per mip into separate 1-level RT images; the sampled image merges them in ResolveOverlap. On Metal (1) Runtime::CopyMip copied only one layer, (2) ImageInfo::MipOf rejected mips 2-4 because small mips degrade to 1D tiling (array_mode differs). Low mips were zero/garbage -> rainbow on rough kit surfaces.
- Fix in lib: CopyMip copies all layers (vk_runtime.cpp); MipOf skips the array_mode check (BB_MIPOF_STRICT=1 restores).
- Not the cause (ruled out): array-layer clamp in MSL, export.cpp ufloat clamp.
- Edit cached MSL only via scratchpad mslpatch.py: the "// msl-bytes" header must match, or the file is silently regenerated.

## Stage B split mode (2026-10-30): WORKS, ~59 fps in match
Native arm64 bbgpu-host renders; shadPS4 is the game side. Env: SHAD_BBGPU_SPLIT=1 SHAD_MAPPING_BASE=400000000
BB_GPU_HOST=~/fifa_metal/bloodborne_mac_port/out/bbgpu-host. Builds: x86 lib (cmake out/gpu), arm64 lib
(ninja -C out/gpu-arm64 bbgpu), host (~/fifa_metal/build_host.sh), shadPS4 (cmake --build shadps4-metal/build) + install.sh.
Details in ~/fifa_metal/PLAN.md "Stage B".

## Brightness (2026-10-30 16:30)
Menus/warm-up fixed by a stopgap x2.5 gain patched into the cached tonemap MSL (files in ~/fifa_metal/patches/,
lost if the shader cache is wiped). Players in match are still much darker than Vulkan (pitch is fine): a
player-shader lighting bug, not exposure. Details and ruled-out list in ~/fifa_metal/PLAN.md (last section).

**2026-10-30 evening (fault relays):** write faults on GPU-protected pages are now handled in the game process
(bbport_split.cpp LocalWriteFault, BB_LOCAL_WFAULT=0 disables; BBGPU_REC_CPU_WRITE on the submit ring; host
Rasterizer::OnCpuWrite). Page kinds come from the host's protect records (read bit 2 = image write-tracked,
bit 4 = droppable image readback; PageManager::num_image_watchers/num_image_read_watchers). BB_ONDEMAND_WRITE_DROP
(default on) drops readbacks of plain render targets on CPU write; block-compressed/uint images and block shadows
are excluded (kits/faces went bad otherwise). BB_HOT_READ pages: polled GPU-written words are written back after
each submit. Diagnostics: BB_FAULT_STATS=1 ([FAULTS] game side, [WFAULT]/[RFAULT]/[ODW]/[CPUW]/[HOTREAD] host).
Autotest: HUD_ALL=1 logs HUD in every state; metal target defaults SHAD_BBGPU_SPLIT=1; ~/fifa_metal/drill_watch.sh
samples both processes in the practice arena. Match fps after: 48-56 open play (was ~40), 30 in crowd views.

**2026-10-31 BRIGHTNESS ROOT CAUSE FIXED:** FIFA's auto-exposure reads a GPU luminance reduction (cs e3c8e227,
512 threads, LDS tree whose tail relies on GCN wave64 lockstep). The port's SharedMemoryBarrierPass skipped
shaders with workgroup != 64, so Metal reordered the LDS accesses and only one SIMD group's values survived ->
exposure stuck at presets (0.4 rain, 1 menus, 2 overcast) instead of adapting (Vulkan 3..30). Fix = upstream
shadPS4's subgroup memory barriers (IR opcode SubgroupBarrier + MayHaveSideEffects + OpMemoryBarrier(Subgroup)).
Hub now matches Vulkan without any gain (BB_RESOLVE_GAIN default 1); rain open play 0.27-0.31 vs Vulkan 0.32.
**Follow-up (flicker):** subgroup barriers alone left a race: the tail runs under `if (tid < 64)` = two 32-wide
SIMD groups on Apple, and a threadgroup barrier inside a thread-id branch is illegal. The pass now if-converts such
branches (cond := true, LDS addresses select(cond, addr, scratch word), merge phis select old value) and uses
workgroup barriers; BB_LDS_IFCONV=0 disables. Static hub exposure went from +-14% jitter to +-1%.
**HUD white fans / shine outside UI panels (2026-10-31):** Scaleform stencil masks (write bit0=1, test EQUAL 1,
write 0) assume zeroed memory; a fresh Metal texture's stencil is 0xff so the masks were inverted (the Vulkan
build has the same bug). Fix: Image::stencil_undefined -> the first pass binding the stencil clears it to 0
(BB_STENCIL_ZERO=0 disables). Per-draw dump tooling: BB_DUMP_PS/BB_DUMP_RT/BB_DUMP_PS_TRIGGER/_STENCIL/_LOGONLY,
BB_STENCIL_LOG (see PLAN.md 09:25).
**Dark players (intermittent, 2026-10-31):** the 2048^2 shadow maps are R32 colour targets that the player
shaders compare-sample as D32; the cache recreated the image R32<->D32 each frame with 16 MB copies and undefined
fresh textures (lit or dark by chance, heavy GPU churn). Fix: Image::depth_twin (D32 twin synced on writes,
BB_DEPTH_TWIN=0 restores). See PLAN.md 11:50.
**Warm-up drill hitches (2026-10-31):** CPU read faults on GPU-composited textures drained the GPU on the host's
GPU thread (15-60 ms each). Now: prefetch of large on-demand images (BB_ONDEMAND_PREFETCH_KB) + the readback wait
moved to the faulting thread (BB_READBACK_GPUWAIT=1 restores). Dark players still recur ~1 in 4 runs even with the
depth twin: cause open (PLAN.md 14:20 has the capture recipe).
**Patch overlay (2026-10-31 14:55):** Custom-metal's download/CUSA02138 -> ~/fifa_perf/overlay/CUSA02138.fip,
built by ~/fifa_metal/make_fip_overlay.py <name> <theme>: full Manual Install by symlink + FIP theme (V5 Purple)
copied on top + lean player/crowd.lua + intro-skip nav. The Manual Install (main build) keeps the Default theme.
Also fixed earlier today: shirt names (micro-tiled small mips), depth remap opt-in (DOF blur), kit/face damage.
Tools: hubcheck.sh, seqcheck.sh (hub+kit vs refs/kit_select.jpg), matchsheet.sh <label> (contact sheet),
`bash ~/fifa_autotest.sh drive main` drives the Vulkan working build read-only; perfdbg target = probe build of
the reference tree (~/fifa_perf/shadps4 branch rain-probe, SHAD_RESOLVE_LOG=1). Weather is set to Rain in the
game's kick-off settings (shared saves). Known open: intermittent 3-5 fps rain runs (GPU 300-700 ms/frame).

- 2026-10-31: FIP asset map in ~/fifa_metal/hud/FIP_ASSET_MAP.md. HUD boards = data/ui/game/overlays/overlay_<pkg><screen>.big; stock pkgs 6 EPL/7 Bundesliga/8 FUT/9 generic. FIP's 98 pkg-9 files are byte-identical to stock; only its 26 EPL files (+ split overlayComponents_6/overlayComponents_NN) are new and untested on Metal. Purple theme is the only real restyle; fifascoreclock.big = pause-menu scoreline.
- 2026-10-31: FIP ball "texture tiled small" = wrong low-poly mesh UV layout, not textures. Fix = ~/fifa_metal/stripify_balls.py (FIP high-poly PC triangle lists -> PS4 triangle strips, prim section 0xd48d7880 4->6, must stay <= ~9094 indices / 3636 verts like stock) + fix_ball_textures.py (RX3 texture header 2048->1024 to match data); side files in /Volumes/SanDiskSSD/fifa_side/{ball_fixed,ball_hp}, overlay rewired by make_fip_overlay.py. Offline check tool: software-render mesh UVs over the decoded BC1 atlas.
- 2026-11-03: DARK PLAYERS root cause = ImageView redirected every "depth compatible" (R32) view of an image with a depth twin to the D32 twin, so the shadow-map pass's colour attachment and the clear's storage view hit the twin and the real maps stayed at zero (no shadows / sometimes dark depending on view creation order). Fixed: twin only for eD32Sfloat (promoted) views (image_view.cpp, image.cpp). Diagnostics kept: BB_TWIN_WATCH, BB_SEQ_AT, BB_DEPTH_PROBE, BB_SHADOW_FORCE, BB_BUF_LOG dumps. To test a patched cached MSL, move metal/pipelines.binaryarchive away first. Rollback point: /Volumes/SanDiskSSD/fifa_side/rollback_20261103/restore.sh + git tag rollback-20261103 in both trees.
- 2026-11-03: the high-poly ball crash is Vulkan-build-only (in-process GPU thread); the Metal split build plays FIP's unmodified meshes (20028 verts tested). ball_originals.py links the originals; make_fip_overlay.py runs it last; balltest.sh <mesh> <label> is the test harness.
- 2026-11-03 latency: BB_FRAME_STATS=1 prints "Latency (flip call -> on screen ...)" per 5 s (Metal presented handler). Fixes: byte-exact on-demand overlap (a constant buffer 128 B past a 93x75 image forced a GPU drain every frame), fences stay pending until the label holds the value (9 CP stalls/frame), async unprotect relays, BB_MIDFRAME_FLUSH_MS, BB_IMMEDIATE_FLIPS (present on arrival + one game-visible completion per vblank tick), BB_FULLSCREEN (run.sh defaults). 60-fps play flip->screen 47 -> 28-34 ms. Tools: lattest.sh, sampleself.py/samplecallers.py (sample files), seqview.py, rawstats.py. FIFA runs replays/close-ups at a 30 Hz flip rate by itself.
- Present pacing: FIFA sets flip_rate=1 after a transient hitch; honouring it as a present divider held the game at 30 fps for whole stretches (baseline), so BB_IMMEDIATE_FLIPS ignores it; slow frames (receive gap > BB_IMMEDIATE_FLIPS_SLOW_MS=24) are held to the vblank tick for even pacing in GPU-bound replays/flyovers. Verified 175432: 60 fps, 0 hitches, flip->screen 28-29 ms.

**2026-11-03 evening (playable snapshot).** Snapshot `/Volumes/SanDiskSSD/fifa_side/playable_20261103/restore.sh`,
git tag `playable-20261103` in both trees: the state the user called "smoother than ever". The intermittent
"slow-GPU state" is the close-up cutscenes (walk-out/celebrations): GPU busy 15-21 ms but the game serialises on
the frame's EOP + the 33 ms flip slot (not memory, disk, fault relays or game CPU; see PLAN.md 22:40). Open-play
flip->screen 27.5 ms = CP lag 6.4 + present 20.6 (GPU 7 + vblank/compositor; layer 3024x1898 is composited,
display is 120 Hz ProMotion, present thread ticks at 60 Hz). Fault relays cost the game 350-500 ms per 2 s in
open play (600-790 relayed image-page writes / 2 s at ~0.6 ms each).

**2026-11-04 (push further round).** Pacing: BB_IMMEDIATE_FLIPS presents every flip on arrival; slow cadence
completes at once (close-up cutscenes 10-30 fps -> 57-60; commit 6822e67). GPU host runs from an app bundle
`~/fifa_metal/host_app/FIFA 16 GPU.app` (run.sh default BB_GPU_HOST; refresh.sh after host rebuilds): Metal
"Direct" + Game Mode On; window-level screencapture of it is black, so fifa_autotest.sh/run.sh capture the whole
screen when the bundle host runs. Relay spin (BB_RELAY_SPIN_US, host sets relay_spin_ns; commit 11f3040) neutral.
The game binary (shadps4-metal) carries its OWN copy of gpu_process.c/bbgpu_shared.h: never bump
BBGPU_SHARED_VERSION without rebuilding shadps4 (host setup fails with status 22). Display sync off
(BB_PRESENT_MODE=Immediate) = 6-7 ms less present latency, opt-in only (tearing risk). Two drawables: no gain.
Launcher: `~/fifa_metal/launcher/FIFA 16.app` (opus subagent; `build.sh --test`; `--cli play/stop`).

**2026-11-04 (round 2).** Crash after a long Career session: StagingBufferPool large cache had no lock (FreeDeferred
from the fault + priority-ops threads vs the GPU thread) -> mutex, commit 9d5765b. Async-landing fault downloads
are UNSAFE (the game recycles memory next to the 93x75 RGBA32F image; a late landing clobbered live data -> 680 ms
GPU frames). ~90% of match fault downloads are of images written in the pending command buffer, so a second
read-back queue cannot help (BB_RB_DIRECT exists, off; commit 84b8e5c). Keyboard poll 4->1 ms in the game binary.
NIGHT MATCHES (floodlit) run at ~1 fps: compute shader cs f48fb40c (98x1x1 groups, 1024 threads, instance culling:
each thread loops `count` placements from a 57-dword type record) takes ~1 s per frame; day matches: 0.05 ms, the
instance buffer is all zeros. Weather/time per autotest match is random (~1/3 night); FIFA saves live in the SHARED
~/Library/Application Support/shadPS4/home/1000/savedata (the user's real saves: do not edit). Probe knobs:
BB_PROBE_SHADER=<hash> BB_PROBE_FIELD=b,dword,stride[;..] BB_PROBE_DUMP=b,records,stride[;..] (rasterizer).
Host app bundle: after copying a rebuilt bbgpu-host into `FIFA 16 GPU.app` it must be re-signed ad hoc
(`codesign --force --deep -s - "<app>"`; refresh.sh does it now) or macOS SIGKILLs it at launch and the game
reports "host exited during the handshake (status 0x9)".
ROOT CAUSE of the 1 fps matches (fixed, commit 7deb4ed): RangeSet::ForEachInRange (buffer_cache/range_set.h) used
boost ICL lower_bound/upper_bound with the whole query interval, which skips overlapping intervals (boost 1.88,
64-bit domain). GPU write-backs then missed ranges, cleared the page bits anyway, and the next CPU-modified upload
put stale guest memory over GPU data. Symptom here: FIFA's DMA-copied type table (b2 of cs f48fb40c) garbage ->
loop counts garbage -> ~1 s/frame; also dark "X" marks on the pitch. Fix: iterate from lower_bound({start,start+1})
(check the previous interval) while lower < end; verified vs brute force. Not weather/night related after all.
