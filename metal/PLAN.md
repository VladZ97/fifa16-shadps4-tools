# FIFA 16 on Metal: side project plan (2026-10-29)

Goal: keep the daily build (shadPS4 Custom-perf, tag playable-60-v1.4) untouched, and build a
separate variant that renders through the Bloodborne port's native Metal path, for the crowd-heavy
views (GPU 19-26 ms at 1080p -> game locks to 30) and higher output resolutions.

What the Bloodborne port is (repo: ~/fifa_metal/bloodborne_mac_port, GPL-2.0-or-later, 221 stars):
- game x86-64 under Rosetta 2 (same as us), its own C HLE runtime (Bloodborne-specific: eboot flattened
  offline, libc/Fios linked in, 77 GPU NIDs + other libs) -> NOT reusable for FIFA (shadPS4's HLE stays).
- gpu/: shadPS4 video core vendored from upstream b4e7ae7 (2026-10-02; ours is 3eecea9, 241 commits
  later; upstream video_core diff between them: 60 files, +2893/-2305) + "bbport:" changes
  (~380 markers) + renderer_metal/ (59 files, 16k lines, native Metal, SPIRV-Cross -> MSL,
  MTLBinaryArchive pipelines, MetalFX/FSR 3.1/TAA) + shim/ (bbgpu C API, overlay, settings, capture).
- host/: native arm64 GPU process; game memory shared via Mach memory entry at identical VAs,
  submit rings + doorbells, cross-process page-protection relays (docs/DESIGN_NATIVE_GPU_PROCESS.md).
- the GPU library needs ~22 runtime_* functions from the runtime (memory region/vma/clamp/is_mapped,
  read/write backing, gpu_protect + set_gpu_hooks, tsc/process time, thread attach/blocked, errno/error,
  file_translate, restart, sampler_flip, context_lock_other).

Hybrid design (what we build): shadPS4 = FIFA's runtime (kernel, libs, memory) + bbgpu as the video core
(their gnmdriver/videoout/equeue registrations replace shadPS4's), driving their Metal renderer.
Stage A (in-process, x86 under Rosetta): link libbbgpu into shadPS4, implement runtime_* on shadPS4's
  Memory/PageManager/thread code, route sceGnm*/sceVideoOut* NIDs to bbgpu_resolve. Measure.
Stage B (split): adopt host/ (bbgpu-host arm64) with shadPS4 as the game side (bbgpu_init_remote +
  split_push + fault relays). Measure.
Stage C: upscalers (MetalFX quality at 0.67-0.75 internal) and resolution options.

Spike M0 (go/no-go):
1. Build their gpu library here: scripts/macos/bootstrap_deps.sh (x86-64 SDL3, FFmpeg, SPIRV-Cross, ...)
   then build_macos.sh --gpu-only -> out/gpu/libbbgpu.dylib.   [needs a permission rule to run]
2. Enumerate the runtime_* contract precisely (declarations) and map each to shadPS4 code.
3. Decide which side owns gnmdriver/videoout/equeue (their vendored copies vs ours at 3eecea9) and how
   the pipeline cache / shader dumps / patches directories are configured (BbGpuConfig).
4. First light: a shadPS4 build (new clone at ~/fifa_metal/shadps4-metal) that boots FIFA to the title
   screen through libbbgpu in-process. Then kit screen GPU ms vs KosmicKrisp (16 ms baseline).

Risks: their video core carries Bloodborne-tuned behaviour (skips a bad bind, reads zeros for freed
data, arena layout for 16 GB Macs); FIFA uses on-demand readbacks/precise mode semantics that we
patched in our tree (texture_cache/buffer_cache) and would need to re-apply on their vendored copy;
the recompiler is 4 weeks behind upstream (they backported correctness fixes).

## Status 2026-10-29 (afternoon)
- Built the port's GPU library (deps/x86_64 + out/gpu/libbbgpu.dylib, x86-64, LTO) on branch `fifa-hybrid` of the
  clone with 4 small changes: BbGpuConfig.metal_layer/layer_scale (render into a layer the host app owns, no SDL
  window of its own), an external-layer WindowSDL constructor, GetUsableRegions widened to shadPS4's guest range
  (0x400000..0xfc00000000), and bbgpu_memory_{register,map,unmap,invalidate} entry points.
- shadPS4 worktree ~/fifa_metal/shadps4-metal (branch metal-hybrid): src/core/bbgpu_bridge.{h,cpp} implements the
  21-symbol runtime contract (region mirror kept by the memory hooks so the library's threads never take the memory
  lock; mprotect for GPU page protection; TryGetBacking/TryWriteBacking for backing access; errno, clocks, path
  translation; fault recovery via runtime_fault_recover). Hooks: MemoryManager::GpuRegister/GpuMap/GpuUnmap replace
  the direct rasterizer calls; signals.cpp tries the bridge first; linker.cpp falls back to bbgpu_resolve for
  libSceGnmDriver/libSceVideoOut/libkernel; libs.cpp/kernel.cpp skip GnmDriver, VideoOut and the event queue;
  emulator.cpp starts the library before InitHLELibs. CMake: ENABLE_BBGPU + BBGPU_ROOT. Runtime switch SHAD_BBGPU=1.
- Launcher version Custom-metal (copy of Custom-perf's user dir), ~/fifa_metal/run.sh (start|play|status|log|shots),
  ~/fifa_metal/install.sh, ~/fifa_metal/bbport.ini (BB_CONFIG).
- Known gaps for later: no replay of mappings made before Init (none expected), shadPS4's window still has its Vulkan
  flag (unused), library's own SDL copy is uninitialised (display refresh falls back to 60 Hz), Bloodborne-specific
  ContextOwner read (diagnostics only), no upscaler motion vectors for FIFA (MetalFX spatial would be the fit).

## Status 2026-10-29 evening
- Library fork fixes since first light: barycentric pull-model interpolation -> plain read (Metal rejects
  interpolant<> on [[barycentric_coord]]); CopySparseMemory reads through runtime_memory_read_backing (the
  recorder thread deadlocked on a precise-mode read fault); BufferCache::ReadMemory drains the draw pipe before
  the download; DownloadImageMemory ported from upstream (tiled images through TileManager::TileImage) with
  ShouldReadbackImage (BB_READBACK_TILED, default 256x256, no depth/HDR/frame-sized); ProcessDownloadImages async
  (BB_READBACK_SYNC=1 restores); image_view format-fallback logging. Bridge: fault recovery checked before the page
  manager; protect-call diagnostics (SHAD_BBGPU_PROT_LOG).
- Findings: BB_READBACKS default Relaxed in the port (black players = no readbacks); Precise made the game stall at
  kit_select_ready/match_preview for minutes (CPU polls a GPU-written value; no faults in samples) and eager sync
  image downloads made everything crawl; GPU watchdog "no progress" hangs at match loading twice (cause unknown,
  watchdog now off so Metal reports). Runner defaults: BB_READBACKS=1, BB_READBACK_LINEAR=1, BB_ARENA_LAYOUT=runs,
  BB_GPU_WATCHDOG_MS=0.
- Next: (1) kit screen + match under Relaxed + image readbacks; (2) if textures/lighting still wrong, port the side
  build's on-demand image readback (protect on GPU write, download on first CPU read, download-before-invalidate);
  (3) the match-load GPU hang; (4) the Vulkan inventory run logged nothing (SHAD_LOG_IMAGES not exported by
  fifa_perf.sh?).

## 2026-10-29 22:25 — BC block shadow (stopped here on request)
- Cause found: GPU texture compression writes BC3 1024x1024 (e.g. 0x238fac400) through an RGBA32Uint
  256x256 storage view (same guest_size, tile 13). Metal can't view BC as uint -> writes lost -> broken
  stadium/city textures, likely the "Impacting Interactivity" kills + loading_drill stall.
- Fix (built+installed, libbbgpu): TextureCache::ResolveBlockShadow / SyncBlockShadow (texture_cache.cpp),
  Image::block_shadow/shadow_of/shadow_newer (image.h), redirect pass in vk_rasterizer.cpp BindTextures
  before the usage-upgrade pass, Runtime::CopyBlockBytes + block-aware CopyImageWithBuffer (vk_runtime.cpp).
  BC->shadow copy before each bind unless shadow newer; shadow->BC on next FindTexture of the BC image.
  Disable with BB_NO_BLOCK_SHADOW=1.
- First run (runs/20261029_222127, STOP_AT=loading_drill): reached loading_drill, 0 "Impacting
  Interactivity" (was >0 before). Not yet checked: textures in shots, match visuals/stutter, FPS.
- Gaps: CPU readback of a BC image with shadow_newer reads stale BC; levels>1 not handled.
- Next: look at shots of that run, then full drive to in_match, compare FPS vs perf; then remove debug
  ([DMAP], [PROBE], RBQ, [BCVIEW], extended fallback log, env toggles).
- 22:56 full run (runs/20261029_225609): with the block shadow it got past loading_drill into the
  walkout cutscene (crowd/players render, still dark, dark smear on a face). About 1 min later the Mac
  hung: WindowServer watchdog timeout 23:01:16 (DiagnosticReports/WindowServer_2026-10-29-230138*.spin);
  0 "Impacting Interactivity" kills in the log. Suspect the GPU was monopolized at kickoff. Need a safety
  guard (smaller command buffers / BB_GPU_WATCHDOG_MS / frame cap) before the next in-match run.

## 2026-10-30 — Precise mode
- BB_READBACKS=2 (Precise) reaches the match; players no longer black; Real Madrid kits mostly right.
  Cost: ~28 fps avg vs 35 Relaxed, p99 ~100 ms.
- Barca kits show rainbow noise. Hypothesis: GPU-compressed BC kit textures written via the block shadow
  are never read back to the CPU. Fix (built, untested in match): ResolveBlockShadow storage branch calls
  QueueReadback(bc) (BB_NO_SHADOW_READBACK=1 disables); DownloadImageMemory calls SyncBlockShadow first.
- Intermittent stall at dialog_ok (empty dialog after title) under Precise: runs 005002, 010726 stalled,
  010153 passed. Game likely polls a GPU-written value (read faults at 0x24fa28500 size 8). Perf build
  handles this with async tiny-buffer readbacks + tick waits (DownloadSmallAsync, async_page_ticks).
- Diagnostics added (remove later): BB_LOG_READFAULTS ([RF] in Rasterizer::ReadMemory), BB_BCVIEW_LOG.
- Always run with BB_GPU_WATCHDOG_MS=2000 (Mac hung once). Keep only the last ~5 runs/ folders.
- 02:00-03:10: loading_drill stall (black 3D scene, UI fine, "PRESS START" ignored) in ~4/7 runs, independent of
  block seed / shadow mips / readback size. Passing runs show heavy frames (~1500 draws) after chants loads; stalled
  runs stay at 0/558 draws. Autotest now samples the process when stuck in a state > STATE_MAX (150 s).
- Fixed UNREACHABLE "unresolvable image overlap with equal memory address" (same addr, 6 mips vs 1 mip padded,
  kit composites): treated as address reuse (BB_OVERLAP_STRICT=1 restores the assert).
- Kit noise: kits don't go through the block shadow; hypothesis = RGBA8 1024x1024 tiled composites exceed the
  256x256 tiled readback limit. Testing BB_READBACK_TILED=1048576.
- 03:20 ROOT CAUSE of the drill (and likely dialog_ok) stall: the process sample showed bb:DrawPrep0 stuck in
  Gcn::ParseFetchShader. Draw-prep workers recover from guest-memory faults with siglongjmp (sigsetjmp(buf,0)),
  leaving SIGSEGV/SIGBUS blocked on that thread; the worker's next fault hangs forever. Fix (bbgpu_bridge.cpp
  HandleFault): pthread_sigmask(SIG_UNBLOCK, SEGV|BUS) before siglongjmp.
- 03:30 run 032907: MATCH_OK, 39.1 fps avg (p99 33-118 ms). Barca kits now right; noise left on some RMA players
  (green specks / pink / rainbow) + orange blotches on ad-board bottom edge. Ruled out: BB_READBACK_ALLFMT (no fix,
  -4 fps), BB_MSL_SAFE_MATH (no fix, -6 fps), block shadow (no TEXDUMP: no GPU-compressed image is synced back in
  the whole run, so kits never go through it). Next: dump >=512 colour render targets sampled in match
  (BB_DUMP_TEXTURES + BB_DUMP_AFTER=150, rtdump4) and decode with the scratchpad venv.
- 05:00 kit noise investigation: BB_READBACK_TILED=4194304 doesn't fix it (-6 fps). Perf build shows RMA kits clean,
  so the noise is Metal-only. Match-time BC dump (BB_DUMP_AFTER_BLOCK): kit textures (BC1 1024) decode clean; BC3
  512 kit masks are alpha-only in guest too (non-bug). Noise also on the goal net and player outlines -> likely
  a pass/state issue, not texture data. Upscaler is off. Testing BB_DISABLE_OPT=fe07ffff400fffff (all bbgpu
  optimizations off) to bisect.

## 2026-10-30 12:55 — kit rainbow noise FIXED
- Cause: env-probe cube (R11G11B10 256^2, 5 mips x 6 faces) is rendered per face/mip into separate 1-level RTs and
  merged into the sampled image in ResolveOverlap. Metal CopyMip copied only one layer; MipOf rejected mips 2-4
  (small mips degrade to 1D tiling -> array_mode differs). Low mips were zero/garbage -> rainbow on kits.
- Fix: Runtime::CopyMip copies all layers; ImageInfo::MipOf ignores array_mode (BB_MIPOF_STRICT=1 restores).
- Clean run 20261030_125147: MATCH_OK, kits clean, 35.5 fps avg (samples 42 36 36 36 36 27; earlier run 39.2).
- Debug logs TEXLOG/UFRT/UFCS/PROBE2 removed. Still to review: quad fix env, vector_alu CVT change, export.cpp ufloat clamp.

## 2026-10-30 13:40 — road to 60 fps: where the frame goes (in-match, kickoff camera)
- In-match now 40-47 fps (p50 16.7 ms, frames alternate 16.7/33). Perf build reference in-match: 34-38.
- Slow frames = command processor CPU time > 16.7 ms (heavy frames 650+ draws: 17-18 ms; normal 480 draws x
  20-26 us/draw = 10-12 ms). GPU itself ~10 ms/frame. The lib runs x86 under Rosetta.
- WaitRegMem spin 22-25%: waits for the GAME's CPU to fill streamed command-buffer chunks (ref 1, func ==,
  sequential addrs in CB memory) - not a GPU stall. BB_SPIN_PROF=1 prints [SPIN]/[SPINW] (liverpool.cpp).
- No gain from: BB_NO_SUBMISSION_LOCK=1 (new toggle, 46.7 vs 45.3 baseline = noise), BB_RB_NOBUFRESOLVE=1.
- Run-to-run variance is large (35-47 fps) and scene brightness has two states (luma ~36 vs ~46) independent of
  these toggles: open lighting issue.
- Biggest remaining lever: Stage B (native arm64 bbgpu-host, host/host_runtime.c exists; Bloodborne uses it by
  default). Expected 1.3-1.7x on the command-processor thread. Several weeks of integration (shared guest memory
  at identical VAs from shadPS4's memory manager, fault relays, HLE split).
- 14:00 lighting: the "dark vs bright" runs are the game's time of day (day: luma ~78, hazy; night: luma ~35,
  dark pitch, players lit OK). Main stadium probe identical in both; ~30 local R11G11B10 probes differ (night
  ~0.18 vs day ~0.35). BB_PROBE_LUM=1 prints [PROBELUM]. Perf can't give a reference: it asserts in
  ResolveOverlap (unresolvable equal-address overlap) at match_preview with this squad.
- 14:20 in-process tuning: DropOndemandCovered (CPU DMA fill/copy that fully covers a pending-readback image forgets
  it instead of downloading; BB_NO_DMA_DROP=1 disables) fired once per run -> no gain. Cached ~29 per-draw/per-bind
  getenv calls (vk_rasterizer, texture_cache). FPS unchanged (41.6 avg; 44-48 open play, 28 in crowd views with
  GPU 16 ms/frame). Two separate limits: command-processor CPU (Rosetta) in heavy frames, and GPU time in crowd
  views -> stable 60 needs Stage B (native GPU process) for the CPU side AND upscaling (Stage C) for crowd views.

## 2026-10-30 15:00 — Stage B: native arm64 GPU process WORKS
- Run: SHAD_BBGPU_SPLIT=1 SHAD_MAPPING_BASE=400000000 BB_GPU_HOST=~/fifa_metal/bloodborne_mac_port/out/bbgpu-host
  (+ usual env). Result: MATCH_OK, 58.8 fps avg (samples 57-60, p99 17 ms in open play); previous run 50 avg.
- shadPS4 fork: SHAD_MAPPING_BASE (memory.cpp PlacementStart), guest memory mirror + pool entry in
  address_space.cpp (Mirror*, runtime_memory_*), src/core/bbgpu_split/gpu_process.c (copied from the port),
  bridge Init split path; runtime_tsc_frequency uses EstimateRDTSCFrequency (clock is null that early);
  SHAD_FAULT_DIAG=1 synchronous fault backtraces (signals.cpp).
- Port: second guest range BBGPU_GUEST_LOW [0x400000000,0xfa0000000) (bbgpu_shared.h, bbgpu_guest_range_ok),
  host reserves it with __GUESTLOW segment (must come BEFORE __GUESTRSV in the link; 0xfa0..0xfc0 is taken),
  host/main.c reserve_range; build: ~/fifa_metal/build_host.sh; arm64 lib: BB_LTO=OFF scripts/macos/build_gpu_arm64.sh.
- Autotest: /tmp/fifa_winid.swift picks the bbgpu-host window when SHAD_BBGPU_SPLIT=1.
- Only one 16 KiB view (0x500010000000) is not mirrored. Rendering + gameplay look right.
- Next: make split the default in run.sh/launcher; keyboard focus (host window vs shadps4 window); crowd views
  (GPU 15-19 ms); remove debug ([SPIN], PROBELUM, DMA_LOG, FAULT-DIAG noise); arm64 lib with LTO.

## 2026-10-30 16:30 — brightness: stopgap in place, dark players OPEN (stopped here on request)
**Scene darkness (menus/warm-up): stopgap applied, user says "perfect".**
- Metal 3D scene was ~0.35x Vulkan in display space (HUD correct). Ruled out: sRGB RTs, Precise readbacks,
  BB_MSL_SAFE_MATH, LUT grading, blend constants, cb[9], BB_GAMMA (presenter gamma, no effect).
- Stopgap: x2.5 gain on the outputs of the only tonemapper, cached MSL 00000c37c824e7df_fragment_4fe8bb17a33b648e.metal
  (exposure ssbo_2[29], curve mode ssbo_2[30]). Files in ~/fifa_metal/patches/: tone_orig.metal, tone_gain.py (G="2.5"),
  mslpatch.py. Reapply: `python3 patches/mslpatch.py patches/tone_orig.metal "$D/<file>" < patches/tone_gain.py`.
  Lost if the shader cache is wiped. TODO: move into the lib or find the root cause.
- x3.5 test: menus too bright, match players still dark -> the match issue is NOT global exposure.

**Dark players in match (OPEN).** Same broadcast camera vs perf (perf run 20261030_161424 shot 161658 vs metal
20261030_161051 shot 161320): pitch/crowd match, players much darker (RMA white kits grey, BAR nearly black).
- Player PS = 8b1b463b (vs 955a08bd) and 5fe99f70 (vs 46c02fcf) = cached 000008b2d0579827_fragment_7f365733ac9837a9
  and 000005ff61c48cc0_fragment_639d1773f7eb8032 (originals backed up in scratchpad as pl1/pl2_orig; cache restored).
  They draw into the scene target 0x466650000 (1920x1080 R11G11B10). Inputs: fs_img6 = shadow map (manual compare),
  fs_img7/fs_img8 (pl1) / fs_img11 (pl2) = texture2d_array sampled with explicit level = env/irradiance cubes.
- Ruled out: forcing the cube samples to level(0.0) -> still dark (so not empty low cube mips).
- Depth targets in match (BB_RT_LOG [DBFMT], added this session): all 1 layer, D32Sfloat; 2048^2 / 1024^2 /
  512^2 shadow-like maps, no cascade arrays -> layer-copy bug for shadows unlikely.
- BB_RT_LOG [RTFMT] now logs one line per (rt addr, fmt, ps) with the vs hash (vk_rasterizer.cpp).
- Next ideas: patch the player PS to output individual terms (albedo / shadow fs_img6 / cube fs_img7) as colour
  and compare to perf; check the shadow-map compare (depth range / reversed Z on Metal) and the SH/light constants
  in ssbo_2; check the player-only light (cb values) in warm-up vs match.

## 2026-10-30 19:20 — MSL patch experiments: the binary archive serves compiled pipelines
- Cached-MSL patches (patches/mslpatch.py) only take effect for pipelines NOT in
  cache/CUSA02138/metal/pipelines.binaryarchive ("N from the archive, M compiled" in the log). Move the archive
  away (backup in patches/pipelines.binaryarchive.bak) before testing a patched shader; everything recompiles in ~2 s.
- Runs 190547 (shadow forced lit) and 191011 (shadow term as colour) were therefore unpatched. 191011 (night,
  Cupra boards) showed players normally lit: the dark-player symptom did not reproduce there. 190547 was a day
  match, strongly washed out/hazy (scene luma ~200-212 vs ~67 at night): the x2.5 tonemapper stopgap over-brightens
  day scenes -> the darkness root cause (exposure?) still needs finding.
- Shader debug patches on file: patches/noshadow_pl{1,2}.py, patches/shadowview_pl{1,2}.py (pl1/pl2_orig.metal).
- 19:25 run 191513 (all 298 pipelines recompiled from MSL, shadow-view patch active): players rendered NORMALLY
  in gameplay and in the corner close-up -> pl1/pl2 (8b1b463b/5fe99f70 era hashes) are not the shaders drawing
  players in these cameras; they belonged to the broadcast/line-up camera of run 161051. Dark players did not
  reproduce in three matches today (190547 day/hazy, 191011 night, 191513 day): treat as intermittent/stadium-
  or lighting-state specific. Originals restored in the cache; archive rebuilds itself.
- run.sh defaults now: SHAD_BBGPU_SPLIT=1, SHAD_MAPPING_BASE=400000000, BB_GPU_HOST=out/bbgpu-host, BB_READBACKS=2,
  BB_GPU_WATCHDOG_MS=2000 -> `bash ~/fifa_metal/run.sh play` is the 50-60 fps path.

## 2026-10-30 19:50 — loading-drill (practice arena) fps drops: measured
- Run 193813 (split, Precise), HUD per tick (autotest HUD_ALL=1, new): drill 108-126 s = 18-28 fps, GPU 18-20 ms,
  frame 36-54 ms; from 130 s (streaming done, same scene) 41-48 fps, GPU 10-12 ms. So the drill scene itself costs
  what a match does; the drop is the loading work: (1) game process CPU-bound under Rosetta: 10_job0-3 ~90% busy
  (asset unpack), Game:Main ~80%, RenderThread 36% (sample: drill_sample_game.txt); (2) the render thread spends
  167/356 samples in bbgpu_handle_fault -> BbSplit::RelayFault -> waiting for the host (relayed page faults from
  Precise readback protections); (3) GPU time doubles while streaming (uploads/detiling on the GPU timeline).
  The host is idle (GpuCommandProcessor 83/1126, MtlRecorder 55/1126 busy): not the bottleneck.
- The pipeline archive makes no difference (run 191011 with 296/298 from the archive had the same drill profile).
- Added BB_FAULT_STATS=1 ([FAULTS] write/read/wait per 2 s, game side, bbport_split.cpp RelayFault) to size (2).
- Autotest: the metal target now defaults SHAD_BBGPU_SPLIT=1 (keys to bbgpu-host, picker prefers its window);
  run.sh's picker prefers a bbgpu-host window whenever one exists. drill_watch.sh = drive + sample both processes.
- Brightness (user, 19:45): "too high" in this match (day) = the x2.5 tonemapper stopgap. A/B toggle added for the
  shadow hypothesis (sun term lost -> ~0.35x scene): BB_SKIP_SQUARE_DEPTH=1 drops depth-only draws into square
  targets (vk_rasterizer.cpp Draw, temporary).

## 2026-10-30 20:35 — write-fault relays: game-local handling (in progress)
- Measured (BB_FAULT_STATS=1, game-side [FAULTS] + host-side [WFAULT]): in a match ~900 write faults/s relayed,
  the render thread waits ~0.5 s per second; host processing is only ~1/4 of that (ondemand 170 ms/2 s, buffer 32,
  texture 22, extend 28). The rest is the relay: game -> host fault thread -> protect relay -> game GpuProtect ->
  reply -> game, four hops, ~0.5 ms each. Menus: 80 us/fault. Fault thread now USER_INTERACTIVE QoS (no change).
- New path (BB_LOCAL_WFAULT, default on): the game's GpuProtect thread keeps a per-4 KiB "kind" byte for the low
  guest range (bbport_split.cpp): 1 = read-only and buffer-tracked, 2 = read-only and image-tracked (host flags it
  with bit 1 of BbGpuProtect.read, set in AddressSpace::Protect from PageManager's new num_image_watchers), 0 =
  anything else. A write fault on kind 1 unprotects the run of kind-1 pages in the 256 KiB window locally and
  pushes BBGPU_REC_CPU_WRITE {range, fault} on the submit ring (ordered before later submits). Host OnCpuWrite:
  texture_cache.InvalidateMemory(range) + BufferCache::OnCpuWrite = memory_tracker ExtendWriteFault(range) (marks
  CPU-modified where not GPU-modified), and on the fault page a pending GPU write-back is dropped (CPU wins; the
  GPU write predates the CPU write in ring order). Kind 2 and read faults still relay.
- Run 201704 (first version, no image flag): local=1800/2 s worked, but a loading stall (host flush of the 256 KiB
  window downloaded GPU data over the CPU's write). Run 202440 (CPU-wins, but texture invalidation over the whole
  window): 22 fps constant, every image in the window re-uploaded per frame. Hence the image flag (run 203x).
- Remaining relayed faults are on-demand image writes (R8 1920x1080/960x540 render targets and the BC block
  shadows, see [ODW]) at 1.5-3 ms each on the GPU thread, ~100-250 ms per 2 s: next target.
- 20:50 status: image flag works (run 203223: 52-56 fps open play, GPU 9.7 ms, match avg 47.4). Image pages
  (kind 2) now local per page (run 203703, false STALL: dark scoreboard OCR; in_match rule widened to the
  LALIGA banner + clock). BB_ONDEMAND_WRITE_DROP (default on): a CPU write into an on-demand image forgets the
  readback instead of downloading (host ondemand time 100+ ms -> 3 ms per 2 s; day match 204350 visually clean).
  Pages unreadable only for image readbacks are flagged (read bit 4, PageState::num_image_read_watchers) and
  written locally too (kind 3). Run 204954: ~3000 local/2 s, host fault processing ~1 ms per 2 s, but still
  ~250 relayed writes + ~100 reads per 2 s at ~2.3 ms each (pure relay latency): added a histogram of the page
  state of relayed writes ([FAULTS] ... relayed-write states:) and [RFAULT] host read-fault timing.
- 21:05 user: "kit textures can be messed up" in the current run. Run 205937 (sunny stadium, hard shadows): RMA
  white kits grey, BAR dark; pitch lit and shadowed correctly -> the known intermittent dark-player symptom,
  reproduced with a sunny sky (run 204954, overcast, same build: kits fine). Regardless, the write-drop policy
  now excludes block-compressed images, their shadows and integer images (DroppableOnWrite); their readback pages
  count as plain read watchers (no local writes), so the GPU-compressed kit textures are downloaded before any CPU
  write as before. Dark players: repro condition = sunny/hard shadows; test BB_SKIP_SQUARE_DEPTH=1 on such a match.
- 21:10 run 210622 (kit-safe drop + spurious retry): relayed writes ~0 (spurious=150/2 s retried locally),
  local ~2000/2 s; kits/faces intact (close-up crop). Match 48-52 fps open play, 30 in crowd views (GPU-bound).
  Remaining: ~30 read faults/s, 13 ms each on the host = the game polling one GPU-written word per frame
  (0x4717fffe0, region 0x4717ff000, gpumod buffer; [RF] log), each a 512 KiB download with a full GPU drain.
- Hot read pages (BB_HOT_READ=<faults>, default 8; 0 off): BufferCache::NoteReadFault counts read faults per
  4 KiB page; at the threshold the page is a hot read page: RegionManager::hot_read keeps it readable while GPU
  modified (UpdateProtection: readable = ~gpu | hot_read) and FlushHotReadPages (from FlushTinyWritten at
  OnSubmit) DownloadSmallAsync's its GPU-modified words after every submission. A poll sees the value one
  submission later instead of draining the GPU. Run 211x tests it.
- 21:20 user (run 211x): too bright (day haze + x2.5 stopgap) and the RMA goalkeeper's shirt messed up ->
  DroppableOnWrite now also requires non-power-of-two (screen-derived) sizes >= 256x128: kit/face composites
  (256x256 RGBA8 etc.) are never dropped. Build + verify after the hot-read run.
- 21:25 run 211338 (hot read pages on): [FAULTS] read=0, relayed write<=5, wait 0.1-0.3 ms per 2 s (was ~1 s),
  local ~1900/s, 3 hot pages (0x4717ff000, 0x471111000, 0x471112000). Open play 54-60 fps at GPU 8.6-10 ms;
  crowd cameras 26-30 fps at GPU 16-24 ms (GPU-bound now). Match avg 40.9 over the sampled minute.
- 21:35 run 211802 (screen-target-only drop): constant 60 fps at GPU 9 ms, but the match simulation froze
  (clock stuck at 07:23, picture re-presented at 60 fps): [CPUW] at 0x4717fff10..50 = CPU writes into the hot
  label page; OnCpuWrite's "CPU wins" unmarked the whole page's pending GPU write-backs, so the polled word never
  reached guest memory. Fix: pending write-backs stay (DownloadSmallAsync covers only gpu_modified_ranges bytes);
  the page is marked CPU-modified as well. Relayed writes now only s4 (0x84: BC composite pages, unreadable,
  image write-tracked) ~30/s at 6 ms (download before the write), the price of correct kit textures.

## 2026-10-30 21:55 — brightness root cause: 3D render targets land in depth plane 0
- Exposure constant (tonemapper buffer 1 dword 29, [TONE] log, BB_TONE_LOG=1) is 1.0 everywhere: not exposure.
- Hub (main menu) 3D regions, Vulkan ref sky 0.508 grass 0.259: Metal original tonemapper 0.304/0.138; identity
  LUT in the shader 0.581/0.617; x2.5 gain 0.716/0.339. So the 3D grading LUT step darkens ~2x more on Metal.
- LUT sampling is correct (probe: sampling fs_img3 at 0.25/0.75 gives 0.285/0.762 = the identity LUT's values),
  the identity LUT pair (img3/img4) is intact; the graded pair (img5/img6, another address each run) is
  generated on the GPU by rendering slice by slice. image_view.cpp binds a 2D view of a 3D image as the 3D
  texture itself (slice 0) and BeginRendering never set the render pass depth plane -> every slice draw wrote
  plane 0; the other 31 planes kept the upload (zeros) -> the LUT darkens everything but near-black inputs.
- Fix: vk_rasterizer.cpp BeginRendering sets attachment.depth_plane = slice for Color3D images. Verify: hub with
  the original tonemapper (no gain) must come back to ~0.51/0.26; then drop the x2.5 stopgap for good.
- 22:05 correction: the 3D render-target depth-plane fix is right in itself (kept) but changed nothing here: the
  LUTs are not rendered slice by slice. Stage-1 LUTs (tile 8, linear) come from a compute copy kernel
  (57f53e35: out = in.zyxw) of CPU-written near-identity tables; stage-2 LUT (tile 19, thick) is CPU-written,
  stored (R=z, G=x, B=1-y) and sampled at (g, 1-r, b) through the T# swizzle dst_sel 6,5,4,7 -> neutral. The
  "identity LUT" experiment was invalid (it fed the permuted coordinates back as colour). Swapping R/B in the
  shader made it worse -> the swizzle is applied. So the LUT chain is neutral in the hub (d28=0) and the
  darkness is upstream. Hub pixels: Vulkan grass (63,68,38) vs Metal (32,34,20) = 0.5x, stands 0.57x, unlit sky
  equal -> lit geometry is missing ~half its light (direct/sun term?). Next: BB_SKIP_SQUARE_DEPTH=1 on the hub.
- Diagnostics added this hour: BB_TONE_LOG=1 ([TONE] constants + image descriptors incl. tile and dst_sel),
  BB_DUMP_VOLUMES now writes .guest_t<tile> and .linear (GPU linear copy) beside each dump and dumps every
  bound volume (self-limited); voldecode.py; hubcheck.sh <label> = drive to the hub, screenshot, luma.

## 2026-10-30 22:30 — brightness root cause (real one): GL-style depth passes clamped to [0, 1]
- [VP] log: FIFA renders some passes with clip_space=0 (MinusWToW) and viewport zoffset 0, zscale 1 -> window
  depth in [-1, 1]. KosmicKrisp (the Vulkan reference) advertises VK_EXT_depth_range_unrestricted and
  VK_EXT_depth_clip_control, so the Vulkan build stores exactly that. Metal clamps the viewport to [0, 1] and the
  vertex stage stores (z + 1) / 2 (emulate_depth_negative_one_to_one). Depth tests stay consistent, but every
  shader that reads such a depth target (shadow-map compares, computed from the light matrices) compares against
  the wrong range -> everything in shadow: hub lit geometry at ~0.5x (ambient only), unlit sky unaffected; the
  bias/compare-function/LUT experiments all null; skipping the shadow draws brightened the grass.
- Fix: PushData::depth_remap (push constant bit per image slot, offset 128; the recompiler's AuxData grew to 132
  bytes, static_assert relaxed to 256 = Metal's kMinPushBytes). TextureCache::FindDepthTarget(.., gl_depth) sets
  Image::gl_depth when the depth target is bound under MinusWToW (BB_DEPTH_REMAP=0 disables); BindTextures sets
  the bit for flagged images (memoized texture sets store their mask); emit_spirv_image.cpp RemapDepth applies
  fma(v, 2, -1) to sampled/fetched/gathered values of flagged images (Dref compares not handled: FIFA has none).
  Shader caches (.spv, metal/, archive) must be cleared after this change (moved to patches/cache_bak_*).
- 22:55 status: depth remap implemented (sampled D32 via PushData::depth_remap + FragCoord.z for GL-style
  fragment passes, HwFragmentRuntimeInfo::gl_depth) and its plumbing verified (BB_DEPTH_REMAP_ALL=1 blackens the
  scene), but the hub grass stays at 0.138 (one earlier run gave 0.210 and two gave 0.066: the hub backdrop may
  vary; hubmulti.sh measures the spread). Shadow maps the compute pass 3ba88f63 reads are R32 colour targets
  written by ps f56f5d1c from FragCoord.z under a DX-style pass (no VS emulation) -> unaffected by the viewport
  issue. The GL-style targets are the scene depth (1920x1080, read by ps 92176db0 -> linear depth R32
  0x464d40000 -> ps 7fe6b93d) and the 1024²/256²/64² maps. Next theory: additive light passes not adding
  (blend state) -> BB_BLEND_LOG=1 logs blend states of draws into the B10G11R11 scene target.
- 23:20 depth chain exonerated: the "linear depth = 1.0" dumps were taken at the title screens (first binds);
  with BB_DUMP_AFTER=40 (address dumps now honour it) the resolved depth target 0x464d40000 holds real values
  (-0.28..1, median 0.988 = GL-style range after the remap). Scene proxies (BB_DISABLE_OPT=1<<48), the local
  write-fault path (BB_LOCAL_WFAULT=0), depth2d_ms reads and the raw-fetch resolve patch all left the hub at
  0.138. Scene renders 2-sample MSAA (EQAA: aa_config 4, cb/db 2). Next: sample-mask/coverage handling for
  EQAA and the lighting passes' blend states (BB_BLEND_LOG compiles now).
- 23:35 hub brightness comes in halvings: Vulkan 0.259, Metal 0.138, Metal with BB_HOT_READ=0 0.066 (grass
  luma). New hypothesis: the game's EQAA resolve (ps 92176db0, custom per-sample loop over 4 coverage samples
  mapped onto 2 colour samples through constants: buffer0 dwords 0-3, weight buffer1 dword 4) accumulates
  only part of the samples on Metal (2-sample images, aa_config 4). Test queued: resolve output x2 ->
  expect grass (63,68,38) = Vulkan while the sky (drawn after the resolve) stays. BB_RESOLVE_LOG=1 staged.
- 23:50 FOUND the brightness mechanism: scaling the EQAA resolve's colour output (ps 92176db0, cached MSL
  000009228c249d24_fragment_68a5eedf928f9e4e) x4 reproduces Vulkan's hub exactly (grass (64,69,37) vs
  (63,68,38); stands 133/144/166 vs 126/136/161; the sky drawn after the resolve unchanged). Constants:
  b0 = [2 fragments, 4 coverage samples, 2 fmask bits, mask 0x3], weight 1. The resolve reads an FMASK that the
  recompiler emulates as the constant 0x76543210 (resource_patching_pass.cpp; the Vulkan reference tree has the
  same constant, so why Vulkan is bright is still open). Experiment: BB_FMASK=<hex> override (00000000 = all
  samples on fragment 0, 44444444 = alternating fragments) with cleared shader caches.
- 00:05 (10-31) resolve path exonerated too: both MSAA samples carry the same data (sample-0-only and
  sample-1-only resolves = baseline), FMASK patterns 0/0x44444444 = baseline, the resolve averages by count.
  So the lit scene itself enters the resolve at ~1/4 of Vulkan's HDR intensity (x4 at the resolve output =
  Vulkan), while readback timing shifts it by another x2 (BB_HOT_READ=0 -> 0.066): a lighting constant
  likely comes from a GPU->CPU readback (pre-exposure / eye adaptation). BB_BUFWATCH=<addr> logs the stage
  that writes the polled page 0x4717ff000 and the values written back.
- 00:25 interim: EQAA resolve x4 (patches/resolve_x4.metal = resolve_orig + patches/resolve_x4.py) installed in
  the cache (archive moved aside); the tonemapper runs unpatched. Reapply after a cache wipe:
  python3 patches/mslpatch.py patches/resolve_orig.metal "$D/000009228c249d24_fragment_68a5eedf928f9e4e.metal"
  < patches/resolve_x4.py. Lead for the cause: the 256x256 HDR luminance chain (ps 22b11334 renders levels
  256..16 at 0x444aa8000..) has m4 (16x16) = 0.5 x m0 on Metal (PROBELUM), m3 = 0.92 x; a box chain keeps the
  mean. The 32->16 pass samples half outside? Vulkan reference unavailable (asserts at match_preview).

## 2026-10-31 00:15 — kit/face textures, blur, and the resolve gain
- Kit/face damage (black Barça shirt, magenta RM face at kit select) = the local write-fault path on image
  pages: BB_LOCAL_WFAULT=0 restored them. Now BB_LOCAL_WFAULT levels: 0 relay all, 1 (default) buffer-only
  pages local, 2 image pages too. Kit select with level 1: kits/faces correct.
- Blurry close-ups = the depth remap (DOF reads remapped depth); it never changed brightness -> opt-in
  (BB_DEPTH_REMAP=1). Kit select players now sharp like the Vulkan reference (refs/kit_select.jpg).
- The resolve shader has two cached variants (the FMASK constant is baked in: 68a5eedf928f9e4e = 0x76543210,
  e6bba2cad0f89564 = 0x44444444 left by the fm44 run and apparently still what the game compiles -> check why);
  x4 must be applied to the variant in use (patches/resolve_x4_noremap.metal). With it: hub 0.529/0.273 and kit
  select stands 0.421 grass 0.301 shirts 0.184/0.578 vs Vulkan 0.466/0.330/0.239/0.622. Decoded loop: output =
  avg over the 4 coverage samples (slots from the FMASK word, all < 2) of b1[4] * colour -> pass-through, so the
  MSAA scene colour itself is ~1/4 of Vulkan's. Cause still open; the gain is a stopgap.
- User queue after brightness: shirt names visible only at certain distance/angle (mip chain of the GPU-generated
  name texture?), HUD/menu edge artifacts (whites over the top-left scoreboard).
- 00:12 resolve gain now in the port: emit_spirv_context_get_set.cpp scales MRT0 of ps 92176db0 by
  BB_RESOLVE_GAIN (default 4; the MSL cache name 000009228c249d24 is the pipeline hash, not pgm_hash). Verified
  with wiped caches: hub 0.529/0.273 (64,69,37)/(133,144,166) = the Vulkan reference. No MSL patches needed.
- 00:12 shirt names: close-up crop shows the name above the number as scrambled glyph pieces. Cause found in the
  tiling path: ImageInfo lays mips smaller than a macro tile out micro-tiled (ImageSizeMacroTiled downgrade) but
  tiling.comp addressed every mip macro-tiled (the reference tree has micro_tiled_mips for this). Added
  ImageInfo::micro_tiled_mips, TilingInfo.micro_tiled_mips (replaces the unused num_slices), and the micro branch
  in the macro kernels (micro function now takes thickness). Built 00:12; to verify on a match (sheet_*.jpg).
- Also seen in match frames: uniform white quads/triangles floating on the pitch and above HUD panels
  (sharp-edged, slightly rotated): untextured sprites. Testing BB_ONDEMAND_WRITE_DROP=0.
- 00:45 match runs after the fixes: sunny (001643) players/kits/names fine, 60 fps open play; overcast evening
  (002603) fine; RAIN (002048): pitch/stands lit (luma 0.22) but far-camera players nearly black (both kits),
  cutscene close-ups lit -> rain/wet player material at gameplay LOD, not exposure. Resolve constant b1[4] over a
  run: 5 (boot), 1 (menus), 0.5 (pre-match), 2 (gameplay) = per-scene exposure settings, round numbers (if the
  Vulkan build's values were ~4x these, that would be the brightness cause: a CPU exposure factor at a fallback).
  Polled page 0x4717fff60/70/80 holds ~383k/508k counts (pixel counts, three slots), not luminance.
  matchsheet.sh now sets BB_RT_LOG=1 so a rainy run can be diffed for rain-only shaders. White quads not seen in
  the last three runs (maybe the tiling fix; unconfirmed).
- 00:55 correction: the game-side x86 lib (out/gpu, 21:23) was NOT rebuilt when the BB_LOCAL_WFAULT levels went
  in (23:44), so every run after 23:45 still handled image-page writes locally and the kits/faces were fine in
  five runs. The kit/face damage therefore correlates with the depth remap being ON (runs 233721/234101),
  not with the local faults (a 2v-1 remap of a dark kit texture gives black; white stays white). The level-1
  default stays (safer); x86 lib rebuilding now (cmake --build out/gpu, LTO).

## 2026-10-31 02:50 — rain investigation (weather now set to Rain in the game's kick-off settings)
- Reproduced in drives (sheet_rainbase/rainhot0/rainskipA/raincap*/lutdump*): open play dark (pitch near black,
  players charcoal), replays/cutscenes bright with NO rain streaks and a clear sky -> the weather effects run only
  in the gameplay camera; the replays are not a reference for the rain look. Needs a Vulkan rain kick-off shot.
- Excluded: readback timing (BB_HOT_READ=0 -> open play 43 fps, still dark); the skipped gameplay shader group
  (750b40f6 7fc9b3e3 c052d49f 0b957557 020cf07e c146c982 420639fd 8eec16c1) removed the rain streaks, darkness
  stayed (and GPU time exploded to 300 ms in goal-kick scenes - side effect of skipping); the grading LUTs:
  the thick-tiled (t19) 32^3 LUT bound in the rain match detiles cleanly (R=z, G=x, B=255-y, smooth; same axis
  convention as the hub's GPU-generated t8 LUT) -> not a 3D tiling bug. [TONE] prints nothing in matches: the
  match tonemapper is a different variant (not 5 buffers/8 images) -> the structural hook misses it.
- Frame analyzer (BB_CAPTURE_TRIGGER) is not wired in this build (OnFlip/BeginPass never called): capdrive.sh
  cannot capture; keep for later if the hooks get added. DebugDumpVolume: BB_DUMP_VOLUME_TILE=<mode> dumps the
  first three volumes of that tile mode (GPU copy .linear + guest copy), BB_DUMP_AFTER honoured.
- White streak/quads: present in rain runs too (user shot: above the scoreboard); not isolated yet.

## 2026-10-31 06:30 — rain: findings so far
- Vulkan rain reference captured by driving the working build (target main): ~/fifa_runs/20261031_054525/
  match_254.jpg (open play luma 0.320, pitch 0.315, stands 0.384) vs Metal rain open play 0.114 (pitch 0.10).
  The white fan above the scoreboard is in the Vulkan frame too -> the game's floodlight glare, not a port bug.
- Pass trace (BB_TRACE_AT=<s>,.. BB_TRACE_DRAWS=n, [TR] lines; vk_rasterizer.cpp cb0 binding): the bright
  cutscene/replay frames use 28 shaders, open play ~58; open-play-only = shadow-map writer f56f5d1c (2048^2 R32
  x2), six full-screen HDR post passes (020cf07e 2ba35068 78819038 d7353f35 da983005 381fb098), scene passes
  5b099f1a 5e9714fb 8b1b463b c6a02ca0 d3ee94b3 c2a913a2, half/quarter-res passes. Skipping the shadow writer or
  the six post passes: no change (0.115). Skipping group A earlier: removed rain streaks only.
- Exposure: the resolve's b1[4] is 0.4 in rain open play (2 in replays, 2 in overcast gameplay, 0.5 pre-match,
  1 menus, 5 boot); CPU-written (ring of constant buffers, no GPU producer). Forcing it to 2 in the shader
  (patches/resolve_exp2.py) lifts open play to 0.22 - half way to Vulkan's 0.32. What the game derives 0.4 from
  is unknown: not the fake occlusion counters (BB_ZPASS_STEP=0 -> still 0.4; the Vulkan build fakes them the same
  way, upstream #3553), not readback timing (BB_HOT_READ=0), not CPU-read GPU memory faults (read=0 in [FAULTS]).
- Intermittent 3-5 fps rain runs (GPU 300-700 ms/frame from the drill on; 6 of 12 runs; not tied to the build,
  env, ODW/CPUW counts). Unexplained; next: BB_ENCODER_STATS / per-pass GPU timing when it happens.
- Fault cost in rain: level 1 relays ~250 image-page writes/s at 0.76 ms; level 2 relays ~30/s at 6 ms (readback
  pages): both ~18% of wall time. Open play 55-60 fps either way when the GPU is normal.
- Tools added: BB_TRACE_AT/BB_TRACE_DRAWS, BB_RESOLVE_WATCH=1 (watches b1[4]), BB_ZPASS_STEP, BB_DUMP_VOLUME_TILE;
  g_bb_bufwatch is dynamic (BB_BUFWATCH env or resolve watch).

## 2026-10-31 06:45 — ROOT CAUSE of the brightness: the game's auto-exposure never updates on Metal
- Probe build of the Vulkan reference (~/fifa_perf/shadps4 branch rain-probe: SHAD_RESOLVE_LOG=1 prints the
  resolve's b1[4]; the ResolveOverlap UNREACHABLE is a warning; runs from build/ with its own user dir =
  symlinks to Custom-perf/user; autotest target perfdbg, runner ~/fifa_metal/perf_dbg.sh). Rain match on Vulkan:
  b1[4] = 1, 3, 3.75, 3.85, 30, 8, 6.3, 3.61, 3.62, ... 2.14, 6.24, 6.47 - continuous, changing every second =
  CPU-side eye adaptation from a GPU luminance readback. Metal only ever shows the presets 0.4/0.5/1/2/5 = the
  adaptation never produces a value. Explains the hub x4 (Vulkan ~4 vs Metal 1) and rain (3.6-6.5 vs 0.4).
- The polled page 0x4717ff000 (+f60/f70/f80, three slots, 8 bytes each) is written by a shader (buffer-cache
  write-backs): (0xc6ad1dd0 = -22158.9f constant, float 383k..890k ~ pixel count). The constant first dword =
  the luminance sum never updates on Metal -> likely a float atomic (CAS loop) the Metal path breaks, while the
  uint count atomic works. Next: identify the writer (BB_BUFWATCH=4717fff70), inspect its SPIR-V atomics.

## 2026-10-31 07:55 — BRIGHTNESS FIXED FOR REAL: subgroup barriers for lockstep LDS code
- Chain: Vulkan probe build showed the game's pre-exposure b1[4] adapts continuously (3..30); Metal stayed on
  presets (0.4/0.5/1/2/5). The value comes from the CPU reading (sum, weight) at 0x4717fff60.. (copied by cs
  3327c37b from the partials buffer 0x455a28b20 written by cs e3c8e227 (reads the 960x540 RGBA16F luminance
  downsample, 512 threads, LDS tree) and cs 2eaab068). Forced write-backs (BB_HOT_PAGE + BB_BUFWATCH_N) showed
  per-workgroup sums 40x too small; a constant-input kernel patch gave exactly 32 threads' worth (one SIMD
  group) of the 512: the barrier-free tail of the LDS reduction (GCN wave64 lockstep) is reordered by the
  Metal compiler. Upstream shadPS4's SharedMemoryBarrierPass emits *subgroup memory barriers* in every block
  for shaders whose workgroup != 64 or when the profile has no LDS barriers; the port's copy returned early.
- Fix: IR opcode SubgroupBarrier (opcodes.inc, ir_emitter, MayHaveSideEffects!, EmitSubgroupBarrier =
  OpMemoryBarrier(Subgroup, AcquireRelease|WorkgroupMemory)) + the pass branch from upstream. Result: 20
  simdgroup_barrier in the reduction kernel; exposure adapts (6.2, 19, 16, ... 3.3, 2.8); hub WITHOUT gain =
  sky 0.493 grass 0.249 (58,65,34)/(121,132,152) vs Vulkan 0.508/0.259 (63,68,38)/(126,136,161); rain open
  play 0.27-0.31 vs Vulkan 0.32. BB_RESOLVE_GAIN default now 1 (off). Shader caches wiped (patches/cache_bak_*).
- Perf note: the barriers only touch LDS compute shaders; the luminance kernels are tiny.

## 2026-10-31 08:25 — FLICKER after the barrier fix: the lockstep tail spans two SIMD groups
- Symptom (user): lighting flickers. Static hub with BB_RESOLVE_LOG=1: b1[4] wandered 2.58..3.40 (+-14%) frame to
  frame instead of settling. Cause: the reduction's barrier-free tail runs under `if (64u > tid)` (one GCN wave).
  On Apple that is two 32-wide SIMD groups; the stride-32 step of thread 0..31 reads what 32..63 wrote one step
  earlier. simdgroup_barrier only orders one SIMD group, and a threadgroup_barrier inside a thread-id branch is
  illegal (the other 14 SIMD groups skip it). Race -> random partial sums -> jittering exposure.
- Fix (shared_memory_barrier_pass.cpp, host SIMD < 64): divergent `if (f(tid))` whose body is one block with only
  LDS side effects is made uniform: cond := true, every LDS address becomes select(cond, addr, scratch) with an
  8-byte scratch word after the wave64 scratch area (info.shared_memory_scratch_size, LowerWave64 now takes the
  max), merge-block phis get select(cond, body, old). The body then gets workgroup barriers (uniform blocks at depth
  0 use ir.Barrier(); only unconvertible divergent regions keep subgroup barriers; merge barriers as upstream).
  Closing block barrier now after the last instruction. BB_LDS_IFCONV=0 disables the conversion.
- Result: e3c8e227 has 3 `if (true)` regions, 24 threadgroup barriers, LDS 1042 u32 (4096 + 64 + 8). Static hub
  b1[4] = 3.60..3.66 (+-1%, the hub video moves). Caches wiped (patches/cache_bak_082008_ifconv). Both libs rebuilt.

## 2026-10-31 09:25 — HUD "white fans" above the scoreboard: inverted Scaleform stencil masks
- Capture tooling: BB_DUMP_PS=<ps,..>|all, BB_DUMP_RT=<addr>, BB_DUMP_PS_TRIGGER=<file>, BB_DUMP_PS_MAX, BB_DUMP_PS_RECT,
  BB_DUMP_PS_STENCIL=1 (sNNN raw stencil), BB_DUMP_PS_LOGONLY=1 (state lines only), BB_STENCIL_LOG=1 ([SPASS] pass
  begins, [SREFRESH] depth refreshes); BB_DUMP_DIR. Files dNNN_ps<hash>_<w>x<h>_<fmt>.raw, convert with
  `magick -size WxH -depth 8 rgba:file`. Sheets in ~/fifa_metal/hud/.
- The HUD: Scaleform (ps 82dd3ab3) into the 1920x1080 display buffer 0x469420000 with depth 0x4688a0000 /
  stencil 0x4691a0000 (D32S8). Mask protocol per element: draw with stencil NEVER + ReplaceTest ref 255 wmask 1
  (bit 0 := 1 in the shape), draws tested EQUAL ref 1 mask 1, then NEVER/Replace ref 0 (bit 0 := 0). The shine
  fans are a 24-index stencil-tested draw. Stencil dumps: the plane was 0xff everywhere (254 where masks had
  been cleared): a fresh Metal texture is undefined (0xff), PS4 memory is zero, the game never clears stencil
  (depth yes: clear_d on ~20% of the passes). So EQUAL 1 passed everywhere except inside the cleared shapes =
  inverted mask = shine outside the scoreboard / outside the team square. Same on the Vulkan build (same cause).
- Fix: Image::stencil_undefined (set when a backing is created without a copy); the first pass binding the
  stencil clears it to 0 (vk_rasterizer BeginRenderingFull, BB_STENCIL_ZERO=0 disables). Match: fans gone,
  shine stays inside the scoreboard. The run hit the intermittent 4-fps GPU state (600-800 ms/frame) - rerun.

## 2026-10-31 11:50 — DARK PLAYERS (intermittent): shadow maps bounced between R32 colour and D32 depth
- User: players dark while the pitch is lit. Metal vs Vulkan crops at the same spot: white kits grey/Barca
  charcoal on Metal in ~1 of 3 runs (runs 092354, 110032, 111607 dark; others lit), pitch luma identical.
- Chain: ps f56f5d1c renders occluder depth into three 2048^2 R32 COLOUR targets (0x45fe90000/0x460e98000/
  0x461ea0000, DX-style pass, writes FragCoord.z); cs 3ba88f63 filters them; the player/kit shaders (c17bb807,
  5fe99f70, fb899662, ...) sample them with image_sample_c = D32 texture (IMGBIND showed the same addresses as
  D32Sfloat). The 512^2 R32 at 0x4463c0000-ish is a menu-only map (bound at hub/kit select, never in matches).
- ResolveDepthOverlap recreated the image at every R32<->D32 transition: 2 recreations + 2 x 16 MB copies per
  map per frame (CopyColorAndDepth through a 128 MB device-local staging ring), fresh Metal textures each time
  (undefined contents: all 1.0 in run 105529 = everything lit, zeros in dark runs = everything shadowed).
- Fix: Image::depth_twin (D32 texture synced from the colour backing when write_serial changed: bumped in
  Runtime::AccessImage(write) and UploadImage; synced in FindTexture, the memoized bind path and Image::FindView
  before a depth view is made). ImageView: depth views of a colour image with a twin are views of the twin
  (SafeViewPixelFormat against the twin's format - the first build crashed on an R32 view of the D32 twin).
  ResolveDepthOverlap no longer recreates for Texture bindings when the twin applies (BB_DEPTH_TWIN=0 restores).
- Result: twin2/twin3 runs lit, 49.7-49.8 fps, GPU max 16.7-25.7 ms (was 20-23 ms lit runs, 600-800 ms in the
  slow-GPU runs). IMGBIND now shows the 2048^2 maps as R32 for every reader. Whether the intermittent slow-GPU
  state was the allocation churn remains to be seen over more runs.
- Tools: BB_REFRESH_LOG=1 ([REFRESH] uploads over GPU-written images, [R32UP] small R32 refreshes, [GPUWRITE]),
  BB_DUMP_R32=<dir> (+BB_DUMP_AFTER) dumps small R32 images GPU+guest, [R32LOOP] bind log.

## 2026-10-31 14:20 — WARM-UP DRILL fps (asset loading before "press to start")
- Measured (BB_FRAME_STATS=1 BB_FAULT_STATS=1, drive STOP_AT=in_match): the drill runs at 60 fps GPU-wise
  (gpu 8-12 ms) but with 5-14 hitches per 2 s of 100-330 ms; spikes show "host->flip packet" 70-160 ms = the
  host's GPU thread blocked. [FAULTS]: 10-40 CPU *read* faults per 2 s at 15-60 ms each (on-demand readbacks of
  the GPU-composited kit/crowd textures the loader reads: SendCommand round trip + tiling dispatch +
  scheduler.Finish() ON the GPU thread) plus ~30 writes/2 s into non-droppable on-demand images at ~10 ms. The
  host sample (`sample bbgpu-host`) is otherwise idle; the game's loader threads are the readers. Image
  refreshes in the window: 530 (263 x a 1200x59 RGBA32F linear image, 1.1 MB, ~5/s; kits 1024^2 RGBA8 x9 each).
  BB_LOCAL_WFAULT=2 (local image-page writes) changes nothing here.
- Fix 1 (prefetch): QueueReadback also queues an asynchronous download (download_images, no drain) for images
  >= BB_ONDEMAND_PREFETCH_KB (128); Image::prefetch_landed records the write_serial that reached guest memory;
  TextureCache::ResolvePrefetchedOndemand lifts the watchers without any GPU work when every touched image has
  landed (Rasterizer::ResolveOndemandImages fast path). Helps only when the read comes a frame or more after
  the write; the loader often reads right away ([ODR] log: landed=0).
- Fix 2 (wait off the GPU thread): DownloadImagesForCpuRead(.., CpuReadWork*) records the downloads, Flush()es
  and returns the tick; the faulting thread waits (FinishCpuReadWork: timeline wait, guest write, unprotect).
  BB_READBACK_GPUWAIT=1 restores the drain on the GPU thread.
- Result (drill window, single runs): hitches 48/41/38 -> 24, avg fps 32-46 -> 50; read-fault waits 15-60 ms
  -> 3-6 ms. Remaining: ~5 ms per relayed write fault (round trip + buffer invalidation), the game's own
  loader CPU time under Rosetta, and the Fs Info logging of the drive runs (play mode logs errors only).
- Dark players recurred once (run 135618, 1 of 5 with the depth twin): the twin removes the recreation path but
  the intermittent cause is not fully understood; dumps of the maps + twins in lit runs (twin_a/b) show zeros
  at kick-off time (shadow pass not yet running) - inconclusive. Next: loop runs with BB_TWIN_LOG=1
  BB_IMG_BINDS=1 BB_REFRESH_LOG=1 BB_DUMP_R32=<dir> BB_DUMP_R32_MAX=2048 BB_DUMP_AFTER=200 until a dark run.

## 2026-10-31 14:55 — FIP content in the Metal build: theme + full asset scripts
- The Metal (and Custom-perf) builds used ~/fifa_perf/overlay/CUSA02138.leanlua: patch data/db, loc,
  sceneassets, teammanagement, assignments and data/ui symlinked, but lua/assets held only the two lean scripts
  (25 other FIP asset scripts came from the stock archives) and the patch root carries the "FIFA 16 Default"
  theme (fip/theme/* sampled: Default 60/60 identical, Purple 32/60) -> stock-looking menus.
- New side overlay ~/fifa_perf/overlay/CUSA02138.fip (make_fip_overlay.py <name> <theme>): the whole Manual
  Install by symlink, the chosen theme's 387 files copied on top (incl. data/ui/game/components/fifascoreclock.big),
  the lean player.lua/crowd.lua, the PS4-fixed ball.lua (patch's), the intro-skip bootcommonflow.nav. The Manual
  Install is not modified (the main build still shows the Default theme; `fip_apply.py theme` would change it).
  Custom-metal/user/download/CUSA02138 -> CUSA02138.fip.
- Verified: hub shows the FIP16 V5 Purple theme; match 46.6 fps avg (60 open play), GPU <= 16.5 ms, failed
  file probes 5848 (lean runs 5697-5866: the extra scripts add none). Scoreboard unchanged in look (the FIP
  LaLiga board was already the active one through the symlinked data/ui).

## 2026-10-31 15:40 FIP asset map (hud/FIP_ASSET_MAP.md)
Scoreboards = overlays/overlay_<pkg><screen>.big; stock PS4 has pkg 6 EPL, 7 Bundesliga, 8 FUT, 9 generic. FIP ships all 98 of pkg 9
byte-identical to stock, and 26 redesigned EPL (pkg 6) files + 20 split overlayComponents_6/overlayComponents_NN. The LaLiga match
used only 9xxx -> stock board with FIP logo/colours. Themes: Purple is the only restyle (Salah == Default for game/*.big);
fifascoreclock.big is the pause-menu scoreline, not the HUD. 64 UI paths missing everywhere are optional probes. Open: EPL match test.

## 2026-10-31 17:30 FIP ball textures "tiled small many times" -> wrong ball MESH, fixed with stripified high-poly meshes
Symptom: FIP balls showed the atlas as dozens of tiny splashes. Not the texture: the FIP texel data is a clean 1024x1024
12-panel atlas (its RX3 texture header wrongly says 2048x2048; fixed copies in /Volumes/SanDiskSSD/fifa_side/ball_fixed
via fix_ball_textures.py, kept for consistency with stock). Offline software render (mesh+UV+atlas) proved the cause: the
low-poly mesh copied over 236 FIP balls on 27 Oct (FIP's own ball_0.rx3, 557 verts) has UVs for a different panel layout;
only FIP's high-poly originals (fip/_overwritten_by_mac_apply/balls-highpoly, PC triangle lists, 14706 indices) match the
atlases, and those crashed the PS4 build (stack_chk at first touch). Stock PS4 ball meshes are triangle strips (prim section
0xd48d7880 = 6, list = 4) with at most 9094 indices / 3636 verts. stripify_balls.py converts each high-poly list into one
strip (greedy, backward+forward growth, degenerate joins, parity kept): ball_131 -> 8444 indices; 202 of 319 fit the stock
limits and are linked into the overlay (/Volumes/SanDiskSSD/fifa_side/ball_hp); the other 117 (3700-3850 verts, ~10-11.5k
indices) keep the low-poly strip until the real limit is known (test pending). Verified in match 20261031_172239: Puma
LaLiga panels correct in hand and on the pitch, no crash, 46.9 fps avg. make_fip_overlay.py re-applies all three rewires.
Stock balls on the Metal build were always fine (run 170535). Manual Install untouched; side files only.
17:45 limit probe: ball_160 (3840 verts / 11522 strip indices) linked as ball_131/141 played a full match without a crash
(run 173209, 46.3 fps). Limits in stripify_balls.py raised to 11522 / 3872 -> 304 of 319 high-poly meshes now linked; the
15 left (3990-20028 verts) keep the low-poly strip and would need decimation.

## 2026-11-03 13:45 — rollback point before the dark-players / latency / big-balls work
Snapshot /Volumes/SanDiskSSD/fifa_side/rollback_20261103/ (restore.sh: Custom-metal binaries + config + caches,
out/ libs + bbgpu-host, ~/fifa_metal scripts, overlay tarball, download symlink; sources tagged rollback-20261103
in bloodborne_mac_port (fifa-hybrid) and shadps4-metal (metal-hybrid)). `bash /Volumes/SanDiskSSD/fifa_side/rollback_20261103/restore.sh`.
Diagnostics added: BB_TWIN_WATCH=1 ([TWINWATCH] every 2 s from the draw path: source R32 and D32 twin value stats of
every twin image; crashed when called from the presenter: open encoder), darkloop.sh <n> <label> (sequential match
drives with it). Latency: Metal presented handler now feeds the spike log's display time (IsDisplayTimingSupported),
and BB_FRAME_STATS=1 prints "Latency (flip call -> on screen ...)" stage means every 5 s.

## 2026-11-03 15:20 — dark players: what the probes established so far (in progress)
- Twin probe at sync time (BB_TWIN_WATCH): all three 2048^2 R32 shadow maps read 100% zero at every player
  draw in every run today (lit-looking matches, 42-58 fps); the D32 twin follows (zero). The maps are cleared
  by cs 3ba88f63 (gfx ring, before the pass), rendered by ps f56f5d1c (FragCoord.z + slope bias into R32 colour,
  DX clip space, viewport z 1/0, 2048 scissor, cull back, no user clip planes, depth test LESS on the 2048^2
  D32 0x45ee50000 which reads 1.0), 30-80 real draws per cascade per frame (prim lists, thousands of indices),
  then sampled ~50 records later. Ordering is right (BB_SEQ_AT ordered log; no async compute at all - all
  dispatches are on the gfx ring). Render pass store actions are Store. So the shadow draws rasterise nothing
  (or write 0). Next: per-draw dump of the map after each shadow draw (BB_DUMP_PS=f56f5d1c).
- Tools added: BB_TWIN_WATCH (probe in SyncDepthTwin + [SMAP] bind log), BB_DEPTH_PROBE=<hex> ([DPROBE]),
  BB_SEQ_AT=<s> ([SEQ] one-second ordered log: draws into the maps, shadow draws with full state, syncs, memo
  binds, access-write call sites, gfx/asc waits+fences, dispatches), seqview.py, rawstats.py.

## 2026-11-03 16:05 — DARK PLAYERS / NO SHADOWS: root cause found and fixed (depth twin views)
Chain of evidence (all with BB_TWIN_WATCH / BB_SEQ_AT / per-draw dumps, 15 match drives):
- All three 2048^2 shadow maps read 100% zero at every player draw, every run, lit-looking matches; the pass
  (ps f56f5d1c, 30-80 draws per cascade per frame, DX clip space, normal viewport/scissor/cull, depth LESS
  against a D32 2048^2 that stayed at 1.0) wrote nothing even with depth test/cull/discard forced off, with
  the pixel shader patched to a constant and with the vertex shader patched to screen-covering triangles.
- Cause: ImageView::ImageView redirected EVERY view of a colour image that has a depth twin to the twin when
  the view format was "depth compatible" (R32Sfloat is). So after the first compare-sample bind created the
  twin, the shadow pass's colour attachment (R32 view) and the compute clear's storage view were views of the
  D32 twin texture: Metal drops those writes, the real R32 image never changed, players sampled zeros
  (= no shadows, "lit"). Whether the RT view was created before or after the twin decided per run whether the
  maps worked (the recreation era had the same race) -> the intermittent dark/lit runs.
- Fix (image_view.cpp, image.cpp): the twin is used only by views whose format is the promoted depth format
  (eD32Sfloat: ImageViewInfo promotes R32->D32 for T#s flagged is_depth), never by render-target, storage or
  plain sampled R32 views. Run 155805: maps carry data (94% far=1.0, occluders 0.2-0.3), twin identical,
  51 fps, overcast/rain match looks right. Pending: a sunny match (hard shadows) to confirm the compare.
- Side findings: the shadow maps are cleared to 1.0 by cs 3ba88f63 on the gfx ring (no async compute in
  FIFA at all: every dispatch is on the gfx ring); the Metal MSL/PSO cache serves compiled pipelines from
  metal/pipelines.binaryarchive - to test a patched MSL file, move that archive away first.

## 2026-11-03 16:30 — patch-grade balls WITHOUT modification on the Metal build
The high-poly ball crash (stack_chk_fail at the first touch) belongs to the in-process Vulkan build's GPU
thread: on the Metal split build (GPU in bbgpu-host) FIP's unmodified high-poly meshes play fine, including the
two biggest (specificball_0_990_0: 20028 verts / 20028 list indices; ball_340: 10841 / 18804) linked as the
match ball (runs 161412, 161748, 162057: MATCH_OK, 51-59 fps, no stack_chk). ball_originals.py <overlay>
[--textures-original] links all 319 originals (and the untouched Manual Install textures) into the overlay;
make_fip_overlay.py applies it last, so the stripified/header-fixed copies stay only as the Vulkan fallback.
balltest.sh <mesh> <label> = the crash test harness (links a mesh as ball_131, drives a match, restores).

## 2026-11-03 16:50 — LATENCY: measurements (BB_FRAME_STATS=1 now prints "Latency (flip call -> on screen)")
- Metal presented handler feeds the spike log's display time (vk_presenter: TakePastTimings, PresentQueue::Commit
  on_presented). Baseline (vblank 60 Hz, frame limit 0): flip call -> on screen 47 ms in 60-fps stretches =
  host->flip packet 14 + queued (vblank tick wait) 9 + submitted->display (GPU frame + refresh) 23.5; 61-68 ms in
  30-fps stretches (queued 25: the game drops to a 30 Hz flip cadence when the GPU misses 16.7 ms).
- BB_FPS_LIMIT=60 (immediate flips with 60 Hz slot pacing): queued 9 -> 5.6 ms in 60-fps stretches, no change at 30.
- New: BB_IMMEDIATE_FLIPS=1 (present on arrival, no slot: ProMotion adapts), BB_MIDFRAME_FLUSH_MS=<ms> (commit
  the command buffer at a render-pass change once <ms> passed: GPU starts the frame while the rest records;
  BbStats::midframe_flushes). Frames-ahead is already 1 (BB_FRAMES_AHEAD). GPU busy 11-15 ms/frame, host 12-22
  us/draw at 365-985 draws/frame, GPU-thread idle 30-50%. Display: built-in 120 Hz ProMotion.
- The GPU profiler (BB_GPU_PROFILE=1) printed no table in run 164512 (only "GPU profile: on"); not pursued.
- 17:10 Per-frame GPU drain found and removed: a 40 KB constant buffer at 0x458f94e80 the game reads every frame
  sits 128 bytes past a 93x75 RGBA32F on-demand image (0x458f6f600+0x25800) on the same 4 KiB page;
  HasOndemandIn (per page) made ObtainBuffer download the image synchronously (Finish = full GPU drain) every
  frame (host sample: 293/5744 CP-thread samples in Timeline::Wait under ResolveVertexBuffers; GPU profile:
  "image download R32G32B32A32Sfloat 93x75" 2.5 ms/frame of bubble). Fix: HasOndemandOverlapping (byte-exact)
  gates the branch; and when a buffer read really overlaps an on-demand image, BB_ONDEMAND_GPU_BUFREAD (default
  on) tiles the image into staging and copies it into the arena range on the GPU (no drain; the bytes land in
  guest memory later through a deferred FinishCpuReadWork, pages stay protected until then). Run 170729:
  bufreads 0, 60-fps stretch 40 ms (host->flip packet 10, submitted->display 25), 30-fps stretches unchanged
  (the game's 30 Hz flip cadence when heavy frames miss 16.7 ms: GPU busy 15.5 ms + host 13 us/draw x 970).
- 17:25 Fence waits: FIFA does ~9 "tiny dispatch, EOP fence, WaitRegMem" sequences a frame. The pending-fence
  shortcut dropped a fence once the draw pipe had passed its packet, but the label is written later by the
  recorder thread (SignalAfterHostCopies), so each WaitRegMem spun on stale memory until the recorder caught up
  (seq log: "gfx-wait ... now 0 pending 0/0 met 0"; GPU profile: 2.8 ms/frame of bubbles around the 1x1x1
  dispatches). Now a fence stays pending until its label holds the value, and the shortcut answers from the
  list regardless of pipe position (BB_FENCE_PIPE_POSITION=1 restores). Also: unprotect relays no longer wait
  (host_runtime.c, BB_PROTECT_SYNC_ALL=1 restores). The slow-GPU run 171154 (GPU 500-700 ms/frame, 2 fps) showed
  no swap activity during the run (swap 8.7 GB used beforehand, 31 of 32 GB in use); cause still open.
- 17:40 Present path: BB_FULLSCREEN=1 (host window created fullscreen) cut submitted->display from ~25 to 14-19 ms
  (the HUD still says "Composited"; with MTL_HUD_ENABLED=0 a touch lower). With BB_IMMEDIATE_FLIPS the game
  free-runs (73-90 flips/s instead of 60: its flip completion came back at once), so Flip() now defers the
  game-visible completion (flip status, BBGPU_EV_FLIP, buffer label: VideoOutDriver::CompleteFlip) to the next
  60 Hz vblank tick while the picture is presented at once. 60-fps flip->screen so far: baseline 47 ms ->
  fence/bufread/midframe/asap 34 -> + fullscreen 29-33 ms.

## 2026-11-03 17:50 — latency: final configuration (run.sh defaults)
BB_IMMEDIATE_FLIPS=1 (present on arrival; the game-visible completion is deferred to the 60 Hz vblank tick,
one per tick, so the game keeps 60 fps pacing: run 174515 hitches 0, p99 27-33 ms like the baseline),
BB_MIDFRAME_FLUSH_MS=3 (commit at a pass change after 3 ms), BB_FULLSCREEN=1 (host window fullscreen). Plus
the always-on fixes: byte-exact on-demand overlap for buffer reads (+ GPU-side copy), fences pending until the
label holds the value, async unprotect relays. Flip call -> on screen in 60-fps play: 47 ms (baseline) -> 28-34 ms.
What remains above that is the game's own frame (input read -> flip, under Rosetta) and the GPU frame (7 ms open
play, 14-16 ms in the close-up/replay phases where the game itself switches to a 30 Hz flip rate).
Slow-GPU run 171154 (GPU 500-700 ms/frame) remains unexplained (no swap activity; 31 of 32 GB RAM in use).
- 17:58 Verification 175432: 59-60 fps, 0 hitches, p99 27-31 ms, flip->screen 28-29 ms, maps live. 175022 same
  in play; its final goal replay/flyover (GPU 15-17 ms, 1140 draws) ran 36-44 fps with 75-87 ms gaps where the
  baseline locked 30 evenly -> slow frames (arrival gap > BB_IMMEDIATE_FLIPS_SLOW_MS=24 ms) are now held to
  the vblank tick. Finding: in the baseline, FIFA's flip_rate=1 (set after a transient hitch) made the host
  present every other vblank, which kept the game at 30 fps for whole stretches (baseline windows: 150 frames
  per 5 s at flip_rate 1); with present-on-arrival the same windows run 300 frames per 5 s.
- 18:30 Final pacing: fast cadence (4-frame avg receive gap <= 24 ms) -> present on arrival, completion
  deferred one per vblank tick; slow cadence -> the vblank tick path with FIFA's flip-rate divider and
  immediate completion (even 30). Verified 181515 (play: 59-60 fps, 0 hitches, p99 28-30 ms) and the slow path
  in 182129 (30 fps windows at p99 33.4, 0 hitches). Run 182129 also hit the intermittent slow-GPU state
  (GPU 35-50 ms/frame from 25 s in, like 171154 at 500 ms): still OPEN; the machine sits at 24 of 32 GB used
  with 8.6 GB swapped by other processes during these sessions, suspected but not proven.

## 2026-11-03 22:40 — playable snapshot + "slow-GPU state" root cause
Snapshot: /Volumes/SanDiskSSD/fifa_side/playable_20261103 (restore.sh), git tag playable-20261103 (both trees;
bloodborne_mac_port 1b55fae). Snapshot of the state the user called "smoother than ever".
Slow phases (runs 171154, 182129, 221136, 221916): they are the close-up cutscenes (walk-out, celebrations: 250-400
draws, DoF), not open play. GPU profile there: busy 11-21 ms/frame but span 35-95 ms, "after a submission,
unmarked" (GPU idle) 55 ms/frame; the game's own flip gaps 60-94 ms; "queued" 26-45 ms (the slow path's
flip_rate=1 grid). NOT memory (swap 0, 83% free), NOT disk (external exFAT SSD at 7-30 MB/s, no spike), NOT fault
relays (71-141 relayed writes / 2 s, 17-184 ms wait; in open play 600-790 / 2 s = 350-500 ms wait per 2 s!), NOT
game CPU (no thread above ~35%). Model: the game serialises on the frame's EOP (CP parse 6-12 ms + GPU 15-21 ms)
+ its own CPU + the 33 ms flip slot -> 30 fps normally, 10-13 fps when GPU busy reaches 20 ms (misses the slot).
GPU time in close-ups: cs 3ba88f63 (1x1x1 groups) 13/frame at 0.34 ms each = 4.6 ms; 510f1e38 (240x135) 9.7/frame
6.7 ms; 87cfc5cc (4x1x1) 48/frame 1.25 ms. In open play 3ba88f63 11/frame = 1.9 ms of the 7 ms GPU frame.
Latency in open play: 27.5 ms = host->flip packet 6.4 + submitted->display 20.6 (GPU 7 + ~13 ms present/vblank;
layer 3024x1898 under the notch -> composited, display is 120 Hz ProMotion, present thread ticks at 60 Hz).
Open-play host CPU: CP 26%, MtlRecorder 17%, draw prep 10% -> headroom for 120 fps on the host side; the game
process runs 4-5 threads at 25-36% each.

## 2026-11-03 23:25 — pacing (item 1) verified + committed; app-bundle host (item 3); launcher
- Item 1 (commit 6822e67): BB_IMMEDIATE_FLIPS presents every flip on arrival; slow cadence completes at once
  (no flip-rate grid). Runs 225039 / 225721: 60 fps throughout incl. the heavy phases that used to drop to 30,
  1-2 hitches per 2 min, flip->screen 26-28 ms. No regression vs playable_20261103.
- Item 2 (tiny dispatches): cs 3ba88f63 = 8x8 threads writing one texel each (one 8x8 block per dispatch),
  3327c37b = 64 threads storing a buffer. Their 0.17-0.34 ms is the encoder switch the game's render->compute->
  render interleaving forces (fence waits at the encoder start), not shader work. Merging would need reordering
  the game's work: not done (regression risk).
- Item 3: the host run from an app bundle (~/fifa_metal/host_app/"FIFA 16 GPU.app", Info.plist with
  LSApplicationCategoryType sports-games + NSPrefersDisplaySafeAreaCompatibilityMode) gives Metal HUD "Direct",
  "Game Mode On", window 3024x1964 (full panel; before: 3024x1898 Composited, Game Mode Off). Use with
  BB_GPU_HOST=".../FIFA 16 GPU.app/Contents/MacOS/bbgpu-host". Window-level screencapture of the direct layer is
  black: fifa_autotest.sh / run.sh capture the whole screen when BB_GPU_HOST is inside an .app (SHOT_FULL=1).
- Launcher (opus subagent): ~/fifa_metal/launcher/ ("FIFA 16.app", build.sh --test, 94 checks; --cli play/stop
  wraps run.sh play). Smoke-tested 23:21: play -> title screen, stop clean.
- 2026-11-04 00:05 Item 4 (fault relays): host-side handling of a relayed write is ~10 us; the game's wait per
  relay averaged 0.6 ms because 60 of ~520 relays per 2 s are page-sharing writes next to the 93x75 RGBA32F
  on-demand image at 0x458f6f600 (the constant buffer 128 B past it): each a synchronous 4.3 ms download
  (258 ms per 2 s). The other ~460 relays cost ~0.15 ms each. Relay spin window (commit) is neutral-to-slightly
  better (run 235026: 25-30 ms latency, 59.3 fps). BB_ONDEMAND_PREFETCH_KB=64 (run 235608) served part of those
  faults from the prefetch (11-60 downloads per 2 s instead of 60) with no clear latency change: left at 128.
  The CPU never reads that image in a match ([FAULTS] read=0 throughout); an exact cheaper path would be a
  separate readback command queue (download without waiting for the frame's queue). Not done.
- Launcher updated by the subagent for the bundle default (105 checks pass).
- 00:10 BB_PRESENT_MODE=Immediate (display sync off, run 000404): flip->screen 17.7-21.8 ms (present stage
  11.5-15.6) vs 25-29 (17-21) with sync on; 59.7 fps, 2 hitches, p99 26.7. Tearing cannot be judged from
  captures; not made default until the 2-drawable sync-on variant is measured (BB_SWAPCHAIN_IMAGES=2).
- 00:20 BB_SWAPCHAIN_IMAGES=2 with sync on (run 000955): submitted->display 13.7-15.6 (from 17-21) but
  flip->submitted (nextDrawable wait on the present thread) 3.4-9.2 ms: the total flip->screen is unchanged
  (22.9-31 ms). Three drawables stay the default. Display sync off (BB_PRESENT_MODE=Immediate) is the only
  real present-stage gain (6-7 ms); offered as an opt-in launcher toggle (tearing risk off ProMotion).

## 2026-11-04 00:30 — snapshot playable_20261104
Default configuration verified (run 002138: 59.6 fps, 2 hitches/2 min, p99 25.6 ms, bundle host window
3024x1964, no crash): on-arrival pacing (6822e67), app-bundle GPU host (Game Mode On, Direct), relay spin
(11f3040), launcher with low-latency toggle (off). Snapshot /Volumes/SanDiskSSD/fifa_side/playable_20261104
(restore.sh; includes host_app + launcher), tags playable-20261104 in both trees. Earlier snapshots untouched.

## 2026-11-04 10:05 — push-further round 2 (in progress)
- User played three sessions this morning (06:48, 07:47, 09:12) with the launcher (lowLatency on). The 09:12 one
  crashed in Career Mode menus: "vk_staging_buffer_pool.cpp:159 FreeDeferred: Assertion Failed! FreeDeferred on an
  allocation that is not held" (host exit 23). Cause: StagingBufferPool::large_caches has no lock; FreeDeferred runs on
  the fault thread (FinishCpuReadWork) and the priority-ops thread (prefetch landing, buffer label writeback) while the
  GPU thread does RequestLarge (emplace_back → vector move) and TrimLarge (erase). Fix: large_mutex in the pool.
- Page-sharing write faults (the 93x75 RGBA32F image, 30/s × 4.3 ms sync drain): DownloadImagesForCpuRead now records
  an asynchronous download (prefetch mechanism, prefetch_issued serial) and flushes, no GPU wait, when the written bytes
  lie outside the image (BB_ODW_ASYNC=0 restores the drain). Counter "async N" in the [ODWC] line. Run 095554 verifying.
- 10:20 Async landing REVERTED: run 095554 collapsed to 1.4 fps / 680 ms GPU frames. The game recycles the memory
  next to the 93x75 image (writes over the image bytes right after the page-sharing write); a download landing later
  clobbered live game data → garbage draw parameters. Lesson: a fault download must land before the fault returns.
- 10:04 run 100416 (sync path + mutex): 59.8 fps, p99 25.5, 1 hitch, 0 crashes → mutex fix committed 9d5765b.
- 10:12 game binary rebuilt (shadps4-metal build/shadps4 → Custom-metal/shadps4): split-mode keyboard poll 4 → 1 ms
  (src/core/bbgpu_bridge.cpp). Run 101xxx with it: 59.2 fps, 0 hitches, latency 23.0 ms.
- 10:25 Direct read-back queue (Metal::Device::ReadbackCommit/ReadbackWait, Runtime::ReadbackImageDirect,
  BB_RB_DIRECT default 2): a fault download of a linear colour image whose last write is already committed goes to a
  second MTLCommandQueue that waits on the shared event for the committed ticks, no Flush, no drain of the pending
  command buffer. Images written in the pending command buffer keep the ordered path (menus: all 400 sampled
  downloads were "pending" — kit composites written and read in the same frame). Match numbers pending (run byjai0v1n).
- 10:45 NIGHT MATCH COLLAPSE (pre-existing, not from today's changes): runs 095554, 101916, 102712 were night
  (floodlit) matches and ran at ~1 fps with 0.7-1.1 s GPU frames; day matches (100416, 101222) ran at 60 fps.
  BB_GPU_PROFILE: one compute dispatch, cs f48fb40c, 98x1x1 groups (LocalSize 1024), takes ~1060 ms per frame.
  SPIR-V (cache 0x00000000f48fb40c_0.spv → scratchpad cs_f48fb40c.metal via SPIRV-Cross): each thread reads a
  57-dword record (buffer 2 = ssbo_3), loops `count` (record dword 10) times over 22-dword placement records
  (buffer 7 = ssbo_8: 3x4 matrix + params), transforms a position, tests 6 frustum planes (buffer 3 = ssbo_4
  dwords 24-47), and appends a 14-dword entry (atomic counter ssbo_9[1], limit ssbo_4[0]) to buffer 9.
  Micro-benchmark (scratchpad/atomicbench): 1e7 contended atomics 0.4 ms, 1000x22 loads for 100k threads 8 ms —
  so neither atomics nor loads explain 1 s unless `count` is huge. Probe run with BB_PROBE_SHADER=f48fb40c
  BB_PROBE_FIELD=2,10,57 to read the counts (weather is random per run; may take several matches).
- The direct read-back queue is untested on a day match (its only run was a night match); verify before snapshot.
- 12:10 The 1 fps matches are NOT night-specific: a daylight+rain match (run 115245, Game Settings: Time of Day
  9:00 PM, Showers) also collapsed, with giant dark "X" marks on the pitch (the culled instances drawn with garbage
  transforms, probably 3D grass tufts); the very next match with the same settings ran at 60 fps. In the slow runs
  the instance buffer (b1, 100k x 48 B) holds data and the type table (b2, 1051 x 228 B) at the match address is
  garbage in the CPU-visible view; in normal runs b1 is all zeros (the shader is a no-op). Hypothesis: the table is
  produced on the GPU (DMA/compute) and the host's copy is lost/clobbered, or a CPU write is missed. Added [WATCH]
  tracing (BB_PROBE_WATCH=<buffer index>: uploads, write-backs, binds, DMA copies, CPU faults on that range);
  rolling 25-s matches (scratchpad/roll_night.sh) until a slow one is caught with the trace.
- 13:55 Root cause narrowed: the type table is DMA-copied on the GPU (registered as a GPU-written byte range), then
  in slow runs its byte range is GONE from gpu_modified_ranges by the time of the 512 KB write-back while the page
  bits are still set → the write-back skips it, unmarks the pages, a 256 KB fault-window extension marks them
  CPU-modified, and the next bind re-uploads stale guest garbage over the table (counts → garbage → 1 s loops).
  No Subtract was logged between registration and write-back; a loss detector (WatchCheckLoss, tids) is in.
  Bundle gotcha: refresh.sh now re-signs the app bundle (stale signature = SIGKILL at launch, status 0x9).
- 15:15 FIXED (7deb4ed): RangeSet::ForEachInRange skipped overlapping intervals (boost ICL lower_bound/upper_bound
  with an interval key) → GPU write-backs dropped ranges → stale re-uploads → garbage type table → cs f48fb40c 1 s
  loops. 8/8 short matches fast with the table intact (before ~1/3 collapsed). Full-length regression run pending,
  then snapshot playable_20261104b.

## 2026-11-04 15:35 — snapshot playable_20261104b
Verified: run 151616 (default config, 120 s): 59.7 fps, p99 27.1, 2 hitches, 0 crashes; latency 24 ms once the stale
crash dialogs were dismissed (they had forced composited presentation: 34 ms). 8/8 short matches fast with the type
table intact. Contents vs playable_20261104: staging-pool lock (9d5765b), opt-in direct read-back + probes (84b8e5c),
RangeSet::ForEachInRange fix (7deb4ed), 1 ms keyboard poll (shadps4-metal, uncommitted tree as before), host bundle
re-signed (refresh.sh + restore.sh re-sign). Snapshot /Volumes/SanDiskSSD/fifa_side/playable_20261104b (restore.sh),
tags playable-20261104b. Open: the Metal HUD reads "Composited" in captures now (latency unchanged at 24 ms); whether
direct scan-out still engages outside captures is unverified.

## 2026-11-06 — app on a second Mac (macOS < 27): GPU host cannot reserve the low guest range (OPEN)
"cannot reserve the guest range 0x400000000-0xfa0000000 (got 0xfc00000000)", host status 12. Before macOS 27 the
emulator starts the plain bbgpu-host (no exec-time segments), which reserves the ranges with an mmap hint. The low
range (fifa-hybrid) lies inside the dyld shared region's submap ([0x180000000, 0xfc0000000); past the cache end it is
one PROT_NONE never-touched entry on 27.0.1), so the hint can never get it: the plain host never worked with the low
range, unnoticed because this Mac runs the -macos27 host. A fix was tried (no-segment path of reserve_range: walk the
range with mach_vm_region_recurse, take it with MAP_FIXED if it holds only that unused tail; worked in a low-range-only
test host on 27) and REVERTED the same night at the user's request (graphics reported broken in the v0.3.1 app; the
change did not touch the -macos27 path beyond a log call, cause not established). host/main.c = HEAD again, hosts
rebuilt, app/out restored from FIFA16-macOS-v0.3.0.zip. app/out/"FIFA 17.app" is a copy of the v0.3.1 build (user's).

## 2026-11-06 — app: saves fail when the launcher's Update folder is set (OPEN, not a permission problem)
Run 20261106_021149: "Failed to open ... CUSA02138-UPDATE/data, Is a directory" then "Opening /savedata0/DATA failed,
backend did not serve the file"; the slot got a 0-byte INDEX and no DATA. Cause: fs.cpp OverlayPath returns
SHAD_UPDATE_DIR for the -UPDATE/-patch probe of EVERY mount (GetHostPath ~l.349), so /savedata0/DATA resolves to the
update folder's "data" directory; /download0 (mods) is searched in the update folder first as well, so update files
shadow mod files (possible cause of wrong graphics with mods in the app; unverified). Dev run.sh does not set the
variable. Fix idea: apply the override only when the mount is /app0 (or /hostapp). Old saves
(~/Library/Application Support/shadPS4/home) copied into ~/Library/Application Support/FIFA 16/saves; the failed
slot moved to .../FIFA 16/saves-failed-20261106.

## 2026-11-06 11:00 — macOS 26 host fix, second attempt (delivered as v0.3.2 candidate, NOT yet run on macOS 26)
Constraint: do not break the game. So the app is v0.3.0 with ONE file replaced, the plain bbgpu-host (the one the
emulator starts before macOS 27; gpu_process.c host_path picks "<host>-macos27" on 27+, so this Mac never runs it).
- Code: host/guest_takeover.h (new) + 7 lines in host/main.c reserve_range, only in the branch for a host built
  without the segment: hint first as before; if not honoured, walk the range (mach_vm_region_recurse); if it holds
  only unused reservation inside a submap (PROT_NONE, never touched) or nothing, take it with MAP_FIXED (mach_vm_map
  FIXED|OVERWRITE as fallback), verify, log; anything in use is named and refused. Test: host/tests/takeover_test.m
  (take / block / walk). Source changes are UNCOMMITTED; dev out/ hosts and host_app were not rebuilt.
- Findings on 27.0.1: plain process: low range = one nested unused entry 0x352af8000-0xfc0000000, hint lands in the
  high area, takeover works; mirrors (mach_vm_map of a memory entry at 0x406200000, 0x469d00000, ...), no-copy
  MTLBuffers on them, compute read/write, buffer and texture blits all correct. A process WITH the pinned __GUESTRSV
  segment has NO shared-region tail in the low range at all (hint honoured): so a full-game run of the takeover path
  is impossible on 27 (the plain host cannot get the HIGH range here: xzone malloc regions sit in it).
- Last time's "broken graphics" (v0.3.1): all four logged app runs on this Mac used bbgpu-host-macos27 with the same
  reservation lines; v0.3.0 and the v0.3.2 candidate both render a match correctly at 60 fps in an isolated data
  folder (work26 harness). Cause of that report not found; it was not the host change. "Update shadows mods" is NOT
  supported: only 3 AppleDouble junk paths overlap between CUSA02138-UPDATE and ~/FIFA16Mods/merged. The saves bug
  with the Update folder set (fs.cpp:349, update overlay searched for every mount) is real and still open.
- Harness: ~/fifa_metal/app/work26 (app_runner.sh + autotest_app.sh target "app": isolated FIFA_DATA_DIR and a copy
  of the saves; keyboard mapping must be copied into <data>/user/input_config, and in the app's emulator build cross
  is keypad 2, so the copy sends key codes 84/88; HOST_PROC_NAME for a differently named host). make_candidate.sh,
  compare_apps.py (bundle diff ignoring code signatures).
- Delivered: ~/fifa_metal/app/out26/FIFA 16.app + FIFA16-macOS-v0.3.2.zip; SSD: "FIFA 16 v0.3.2.app" beside the
  untouched "FIFA 16.app", and FIFA16-macos26-check (the takeover test). ~/Applications and app/out untouched.

## 2026-11-06 12:00 — v0.4.0: mods inside the app (side menu, compiled engine, optional)
App = v0.3.2 (out26) with only the launcher, run.sh and Resources/fifamod replaced (make_mods_app.sh; emulator, hosts and
libraries byte-identical). Engine: ~/fifa_metal/app/engine = git worktree of ~/FIFA16Mods, branch app-engine, UNCOMMITTED;
live ~/FIFA16Mods/fifamod.py untouched. New in the engine: FIFAMOD_APP (no shadPS4 links, no -mods sibling unless it
exists), FIFAMOD_RESOURCES, FIFAMOD_7ZZ, optional base patch, configure/state/details (JSON), check_source (refuses
system folders, apps, too little disk), SIGTERM cancel. Parity with the live tool: 11,719 merged entries identical.
make_engine.sh compiles with python.org 3.10 (pyenv/Homebrew Python pulls Homebrew dylibs with minos 27: would not load
on macOS 26). Launcher: Model/ModLibrary.swift, App/ModsModel.swift, App/ModsView.swift; side menu; Use mods switch
(settings.modsEnabled; off = no overlay and run.sh points SHAD_MODS_DIR at an empty folder, else <game>-mods stays active);
Advanced Settings folds the bundled items; Edit menu got Cut/Paste/Undo (Paste never worked). 126 model checks incl. real engine.
Matches (isolated data): off = stock game; full library = La Liga scoreboard, Camp Nou, 60 fps; fresh library without
base = UCL scoreboard on the stock game. Not tested: Career saves with mods off; macOS 26; drag and drop by hand; Update
folder saves bug (fs.cpp:349) still open. GUI test notes: keyboard layout breaks `keystroke`, use key codes; synthetic
`click at` misses Form rows, use real CGEvents (work_mods/mouse).

## 2026-11-06 23:30 — macOS 26 host, third attempt (v0.4.1): stub executable + libbbhost.dylib, plain host re-execs
The user's macOS 26 run of v0.4.0: low range 0x400000000-0xfa0000000 refused, "4 mapping(s) in use": libmalloc's
xzone reservation (12300 MiB + two 4 MiB tag-2 regions + 12268 MiB = ~24 GiB, random address) sat at 0x642000000;
on 27 the same reservation lands in the HIGH range (that is why only the -macos27 host works here). No Malloc* env
setting removes it (MallocSecureAllocator=0, MallocNanoZone=0 tried). The takeover from v0.3.2 cannot help: the
regions are live heap. Exec-time segments are the only way to get a range before libmalloc; PR #7 found that on 26
a pinned/4 GiB+ zero-fill segment in an executable WITH CODE breaks dyld's flat-namespace lookups into that
executable (libbbgpu.dylib's -undefined dynamic_lookup of the 22 runtime_* callbacks).
- Fix: bbgpu-host-macos26 = host/stub_main.c (one call) + the two pinned segments; all code in
  out/gpu-arm64/libbbhost.dylib (main.c with -DBBGPU_HOST_MAIN=bbgpu_host_main + host_runtime.c), so no lookup
  targets the executable. The plain bbgpu-host (what the emulator starts before 27) is unchanged until its
  reservation fails; then reexec_segment_host() execv()s the -macos26 sibling (same pid, env BBGPU_HANDSHAKE, stdout
  pipe, registered handshake port all survive exec: verified by a full match on 27 with -macos27 removed from a test
  bundle: "becoming ...-macos26", handshake done, La Liga match 60 fps). Loop guard BBGPU_REEXEC=1.
- Emulator, bbgpu-host-macos27 and libbbgpu.dylib untouched (compare_apps: bbgpu-host differs, two files added).
  ~/fifa_metal/build_host.sh builds all three; make_app.sh ships them; app/make_host26_app.sh <ver> [base] [--no-macos27]
  patches a base app (default out_mods v0.4.0) -> out_host26 + zip. SSD: "FIFA 16 v0.4.1.app".
- Not verifiable here: dyld on 26 loading the stub (the reporter's 1 GiB pinned test segfaulted before main; the
  4 GiB+ ones only failed the lookup). First signal on the 26 Mac: run
  ".../FIFA 16 v0.4.1.app/Contents/Helpers/FIFA 16 GPU.app/Contents/MacOS/bbgpu-host-macos26" by hand: expect
  "pid ..., native arm64" + "not started by bb-probe"; a dyld error there means the stub approach is dead on 26.
- Pre-existing quirk seen on the way: the bundled libbbgpu.dylib carries an absolute LC_RPATH to this Mac's
  deps/arm64/lib, so on THIS Mac the shipped host loads SDL/ffmpeg from the dev tree (other Macs: bundle copies).

## 2026-11-07 — macOS 26 host, fourth attempt (v0.4.2): no flat-namespace lookups at all
v0.4.1 on the 26 Mac: re-exec worked ("becoming ...-macos26"), then dyld: "symbol not found in flat namespace
'_runtime_disabled_optimizations'" although the symbol was in libbbhost.dylib. So on 26 a pinned-segment executable
breaks EVERY flat lookup in the process, not only those into the executable. v0.4.2: libbbhost.dylib = the renderer's
own arm64 objects (out/gpu-arm64, current per ninja -n, bit-identical to the shipped libbbgpu.dylib bar 2 header
bytes) linked with the same CMake link line minus the -Wl,-U,_runtime_* flags, plus host/main.c + host_runtime.c:
no undefined runtime_* left (nm -u), no libbbgpu dependency; the stub links only libbbhost. ~/fifa_metal/build_host26.sh
(called from build_host.sh). Verified on 27 via --no-macos27 package: re-exec, handshake, La Liga match, 60 fps.
Still untested on 26. make_host26_app.sh zip bug fixed (pipefail on the smoke run). SSD: "FIFA 16 v0.4.2.app".

## 2026-11-07 — v0.4.3: macOS 26 host still dies in dyld; in-process fallback + loader probe kit
v0.4.2 on the 26 Mac: "becoming ...-macos26" then the stub died with SIGTRAP (status 0x5), no dyld message: past
symbol binding this time, before main's first say(). So macOS 26's dyld breaks a pinned-segment executable in more
than one way (PR #7's 1 GiB pinned test also died pre-main). Nothing more to guess from here; two things instead:
- Fallback in app/run.sh play: after launch, wait up to 10 s for "GPU process: host pid" (ok) or "the GPU process
  could not start"; on the latter, unless SHAD_BBGPU_SPLIT was given explicitly (SHAD_BBGPU_SPLIT_SET), relaunch with
  SHAD_BBGPU_SPLIT=0 (renderer inside the emulator, x86 under Rosetta: the pre-split path; first log kept as
  emulator-gpu-host.log). Verified on 27 with BB_GPU_HOST=<plain stub that cannot reserve>: fallback kicked in,
  "renderer started on the window's Metal layer", boots at 60 fps. Full in-process match: see below.
- Probe kit on the SSD: FIFA16-host26-kit/run.command runs stub0 (no segment), stub1 (pinned both = v0.4.2), stub4
  (pinned low only), stub7 (__TEXT at 0x300000000 + pinned both), stub8 (pinned 1 GiB each), with DYLD_PRINT_* traces,
  collects ~/Library/Logs/DiagnosticReports/stub*.ips into results/. All five reach main on 27. ld refuses __TEXT above
  the pinned ranges ("address is out of order") and a huge unpinned segment cannot start above the shared cache.
- host/main.c reserve_range now also accepts any __GUEST* segment covering the range (for layouts where one segment
  covers both). Scan of all 34 Malloc* env switches on 27: none removes the 24 GiB reservation.
- make_host26_app.sh now also copies app/run.sh. SSD: "FIFA 16 v0.4.3.app" (= v0.4.2 + run.sh); harness
  autotest_app.sh honours a preset SHAD_BBGPU_SPLIT for the app target.

## 2026-11-07 — v0.4.4: the macOS 26 cause found (libmalloc), 20 GiB low reservation
Kit results from the 26 Mac (26.3, 17 GB; app/work_mods/host26/results_26_run1): stub1/4/7 (46.5 GiB low segment)
die in libSystem_initializer -> __malloc_init -> xzm_main_malloc_zone_init_range_groups: "BUG IN LIBMALLOC: pointer
range initial reservation failed" (SIGTRAP, .ips asi). stub8 (1 GiB pins) reaches main. So macOS 26's xzone malloc
needs a 24 GiB window BELOW 64 GiB at process start (every reservation seen on 26 ends under 0x1000000000) and
aborts without it; 27's malloc goes elsewhere (0x7xxxxxxxxx). Not dyld at all. v0.4.3's fallback worked on 26:
in-process renderer, match at 30-33 fps (user's emulator.log).
- Fix: host/guest_reservation_low26.s = 20 GiB __GUESTLOW (0x400000000-0x900000000): covers the system managed area
  above the base (16 GiB) plus 4 GiB; [0x900000000, 0x1000000000) = 28 GiB stays free for libmalloc. main.c
  reserve_range takes the covered part only and sets bbgpu_low_reserved_max; host_view_apply refuses views beyond it
  (one say() + fail_view E2BIG). Game data: highest low-range GPU protect address seen 0x4717ff000 (+1.8 GiB).
- On 27 via --no-macos27 package: re-exec, "segment covers it up to 0x900cdc000 (20 GiB)", La Liga match 60 fps, zero
  refused views. v0.4.4 = v0.4.3 files + new bbgpu-host-macos26/libbbhost; SSD "FIFA 16 v0.4.4.app"; kit on the SSD
  now has stub9 (20 GiB low + high pinned = v0.4.4's layout) and stub10 (20 GiB low only). If stub9 traps on 26 but
  stub10 passes, drop the high pin (the hint worked for the high range on 26 in all three user logs).

## 2026-11-07 — v0.4.5: SDK 12 stamp makes libmalloc skip the xzone pointer range (the actual fix)
Kit run 2 on the 26 Mac: stub9 (20 GiB low + high) and stub10 (20 GiB low only) abort the same way; only the 1 GiB
pins pass. So any sizeable pin below 64 GiB loses against 26's xzone "pointer range" (random placement, few tries).
Finding on 27: libmalloc chooses the allocator by the MAIN EXECUTABLE's linked SDK (LC_BUILD_VERSION sdk): stamped
sdk 12.0 (-Wl,-platform_version,macos,15.0,12.0; sdk 13/14 still xzone) a process has NO malloc regions in either
guest range (takeover_test walk: 0 in use), i.e. no pointer range at all. Applied to the plain bbgpu-host and to
bbgpu-host-macos26 (full 46.5 GiB low segment again; the partial-reservation code stays, unused). -macos27, emulator,
libbbgpu untouched (sdk 27). On 27 the stamped PLAIN host now reserves both ranges by itself (high via hint, low via
takeover) - re-exec no longer needed here; both paths played a full match (--no-macos27 package, and BB_GPU_HOST=stub):
La Liga, 60 fps, screenshots fine, so the old-SDK stamp does not disturb Metal/SDL. Kit: stub11 (sdk12 pinned both),
stub12 (sdk12 no segment: shows whether the hints work on 26). SSD: "FIFA 16 v0.4.5.app". Untested on 26 as of writing.
Caveat: "linked before macOS 13" compatibility paths in system frameworks apply to the host process; nothing seen.

## 2026-11-07 — v0.4.6: saves fix (emulator), isolation from other shadPS4 installs, no migration prompt
v0.4.5 runs with the native host on the 26 Mac (user: "runs perfect now"); the game then "cannot save and exits".
Not permissions: the update-overlay bug (fs.cpp GetHostPath applied the -UPDATE/-patch overlay to EVERY mount, so
/savedata0/DATA resolved into <update folder>/data, a directory on case-insensitive volumes). Reproduced here with an
empty saves folder: INDEX 0 bytes, no DATA. Fix: the update overlay only for /app0 and /hostapp paths (as -mods
already was). Emulator rebuilt (ninja, tree = HEAD + fs.cpp + user_manager.cpp; shipped binary was bit-identical
to the previous build bar signature/uuid bytes).
Isolation audit (user asked that the app never touches another shadPS4 install): the renderer library's own
path_util (bloodborne port copy, in the x86 emulator AND the arm64 host) ignores SHAD_USER_DIR and was writing
shader caches (1082 files), the Metal cache and custom_trophy/Notice.txt to ~/Library/Application Support/shadPS4.
It honours BB_GPU_USER_DIR: run.sh exports BB_GPU_USER_DIR=$DATA/user and BB_CAPTURE_DIR=$DATA/captures. run.sh
also no longer pkills every shadps4/bbgpu-host on the Mac: own_emulators()/own_hosts() match this bundle's paths;
the launcher's "Another shadPS4 is running" alert leaves it running ("Play Anyway"). Nothing is read from another
install (the app ran on a Mac without shadPS4).
"Save Migration" SDL prompt (user_manager.cpp, shown on the first run with a fresh saves folder, before looking for
old files): removed, TransferOption::Nothing. The launcher's saves folder is the only save location.
make_host26_app.sh: WITH_EMULATOR=1 / WITH_LAUNCHER=1 copy the rebuilt emulator (rpaths fixed) / launcher.
Harness note: never `pkill -f autotest_app.sh` from a command whose own line contains that string (kills itself).

## 2026-11-07 — v0.4.7: FIP 9.0 install (multi-part RAR, 44 GiB unpack, unrar), "kit file inappropriate"
User: installing the FIP archives fails with "something about a kit file being inappropriate". Reproduced with the
compiled engine in a scratch library (store APFS, mods folder on the SSD): (1) the engine always unpacked into the
store's .tmp on the internal disk: FIP 9.0 unpacks to 44.1 GiB (109,811 files), the Mac had 23 GiB -> "No space
left"; (2) then bsdtar ran as fallback and died at the 2 GiB volume boundary (kitnumbers_489_10.rx3: "Too small
block encountered: Inappropriate file type or format") - the message the user saw, hiding the real error; (3) the
real error: 7-Zip 23.01 (Homebrew) reports "Unsupported Method" for 92,751 entries of the main V9.0 archive (RAR5
m3:24), while RARLAB's unrar 6.12 (Caskroom) decodes it; face packs and V9.x updates are m3:23 and fine with 7zz.
Engine: first_volume() (partN.rar / .rNN / .7z.NNN -> first part, mod name without the suffix, refuses an orphan
part), archive_unpacked_size() (7zz l summary), pick_tmp_base() (unpack on the library's volume when it has
room, else the mods folder's volume - the move then is a rename; refuses with both numbers), clear_tmp() cleans
both, extract(): bundled unrar first for .rar (FIFAMOD_UNRAR), no bsdtar for multi-part, all extractor errors
reported. make_engine.sh bundles unrar + LICENSE-unrar.txt (license 3a: UnRAR components may be distributed
separately). Launcher: ModEngine.firstVolume (queue a volume set once), FIFAMOD_UNRAR in the environment.
Tests: 136 (multi-volume 7z from part 3, orphan part refused, firstVolume patterns). v0.4.7 = v0.4.6 + engine;
SSD "FIFA 16 v0.4.7.app". FIP 9.0 full install into the scratch library (fifa_side/fiptest) running at the time
of writing; its result decides whether v0.4.7 stands.
