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

## 2026-11-09 — all open performance + stability items (session started 06:30)
Order of work: baseline measurements (dev run.sh now points at host_app/"F16 GPU.app"; autotest drive mode with
VIS_STATES=none because the reference images predate the FIP theme) -> small items (shader-cache seed, relay spin
core gate, 120 Hz vblank trial, direct read-back day match, block-shadow mips) -> encoder-split removal for the
game's tiny dispatches (BB_DEFER_CS) -> memory-pressure repro for the slow-GPU state -> deadlock loop.
- Shader cache seed (libbbgpu bbgpu.cpp SeedShaderCache): BB_SHADER_SEED_DIR=<dir>/<serial> copied once into the
  user cache (when it has no metal/pipelines.binaryarchive), BB_SHADER_SEED=0 skips. app/run.sh exports it when
  Resources/shader_seed exists; app/make_shader_seed.sh collects the dev cache (33 MB: 429 spv + 452 MSL + archive);
  make_app.sh / make_host26_app.sh (WITH_SEED=1) ship it.
- Deferred dispatches (BB_DEFER_CS=<max groups>, default 64; 0 = off): DispatchRecord hands a small dispatch
  issued inside a render pass to Rasterizer::TryDeferDispatch instead of scheduler.EndRendering(); the pass-end
  hook (before the deferred copy-shader copies) records them after the pass. Conflicts flush them first:
  BindResources (descriptor ranges of the next command: buffers by V#, images by an upper bound of the T#'s
  bytes), OrderAccesses (vertex/index reads, bound images incl. attachments, with written flags in the new
  bound_images_written), buffer-cache uploads (SynchronizeMemory), CPU read-backs (ReadMemory window,
  DownloadSmallAsync), texture-cache downloads/refreshes (by guest range; a block shadow stands for its BC
  image), DMA CopyBuffer/FillBuffer. Not deferred: dispatches touching the open pass's attachments, GDS/special
  buffers, uses_dma shaders, while copies are deferred, indirect dispatches, with the draw pipe or the upscaler.
  Frame stats print "deferred dispatches N (M conflicts)". The flush keeps the caller's binding state (the hook
  runs between a draw's BindResources and its recording).
- 07:12 diag run (old library, open play after kick-off): 60 fps, GPU busy 8.0-8.7 ms/frame, 345-380 draws/frame,
  GPU thread 13 us/draw idle 65%, latency 25.5-27 ms. GPU profile (segments/frame): "(after a submission,
  unmarked)" 6.7 ms; tiny dispatches cs 87cfc5cc 4x1x1 x44/frame 1.4 ms, cs 513b88d5 2x1x1 x44 1.3 ms, cs 3ba88f63
  1x1x1 x10 1.0 ms, cs 3327c37b 1x1x1 x4 0.6 ms = ~100 small dispatches and ~4.3 ms of segment time per frame,
  the target of BB_DEFER_CS. BCVIEW: one BC3 1024 lv1 kit sampled through a 256x256 uint view; no [BCSKIP]
  (no mip-level storage view in a short match: the replay case needs a long match, chain4).
- Harness: the FIP scoreboard OCRs without team names, so drive mode never saw in_match and kept pressing cross
  in the match; fifa_autotest.sh now also accepts the clock plus a player indicator ("7 V. VINI JR.").
- 07:18 ctrl (new lib, BB_DEFER_CS=0): MATCH_OK, 58.9 avg; open play 60 fps GPU 9 ms, cutscene phases 54-58 fps
  at 740-890 draws, GPU 13-16 ms (the crowd/close-up limit). 07:22 defer (BB_DEFER_CS=64): MATCH_OK but
  "deferred dispatches 0.0": nothing was deferred, because every compute shader binds a non-guest buffer type
  (IsSpecial covers Flatbuf/ReadConst and SharedMemory stand-ins, not only GDS). Fixed: only GdsBuffer declines;
  BB_DEFER_CS_LOG=1 prints the first declines with their reason. That run's 54.6 avg / 44 fps cutscenes with the
  GPU at 14 ms is run-to-run variance (host->flip packet 14 ms vs 5-7: a slower CP phase), not the change.
  Slow-frame profiles show the hitches: kit composites (R8G8B8A8 2048 upload 28 ms, BC3 1024 download 6.6 ms,
  R32G32B32A32Uint 256 download 53 ms) during cutscenes.
- 07:27 vblank120 (BB_VBLANK_HZ=120, deferral off): the game is NOT locked to 60: menus and the match preview ran
  at 91-97 fps (GPU 10 ms busy 95-98%, "frame prep" 4 ms, flip->submitted 5-7 ms, latency 39-40 ms). Then the
  drill loading screen ("START") froze for 61 s and the harness stopped the run (no sample taken: the frozen-
  picture path did not sample; fifa_autotest2.sh now samples the game and the host there). Whether the 120 Hz
  vblank triggers the match-load deadlock or the drive pressed the wrong button is open: vblank120b repeats it.
  Control clock speed at 60 Hz: ~2.3 game-seconds per wall-second in open play (clockspeed.sh on the shots).
- 07:31 spin0 (BB_RELAY_SPIN_US=0): MATCH_OK 59.9 avg, latency 26.4-27.6 ms (ctrl 25.7-36.5), 23 hitch windows
  both. The spin buys nothing on this 8-core M1 Pro: host/main.c now defaults the window to 0 on Macs with 8 or
  fewer logical processors and 100 us above (BB_RELAY_SPIN_US overrides; the host logs the choice).
- 07:36 rbdirect (BB_RB_DIRECT=2) on a daylight match: MATCH_OK 59.3 avg, latency 23-28 ms, 22 hitch windows (ctrl
  23), kits/crowd/boards correct in the shots. The direct read-back queue is now the default in run.sh (dev and app).
- 07:40 defer2 (GDS-only decline): still 0 deferred. BB_DEFER_CS_LOG: every dispatch declined as "capture or
  upscaler": TemporalUpscaler::Enabled() is true for FIFA (the settings object), although it only acts on
  Bloodborne's trigger shader and the reduced scene. The condition is now RasterScaling() (the upscaler's own
  scene); rebuilt. The long match and the heavy-phase run (BB_DEFER_CS=64) are the first real deferral runs.
- 07:45 vblank120b (BB_VBLANK_HZ=120): MATCH_OK this time (the earlier stall was the drive at the drill card, not
  the game). In the match the game ran 52-65 fps (GPU 7.5-12 ms, worst frames 57-68 ms), and the match clock ran
  4.3 game-seconds per wall-second against 2.3 at 60 Hz: FIFA 16 steps its simulation once per vblank, so a
  120 Hz vblank is a 1.9x fast-forward. 120 fps therefore needs the simulation decoupled from the vblank count
  (a game patch, not a renderer change); presenting at 120 Hz without the game producing 120 frames would mean
  frame interpolation, for which the game gives no motion vectors. Not pursued further; 60 Hz stays.
- 07:49 memtest (20 GiB hog, deferral off): MATCH_OK 59.6, GPU 8.3-9.7 ms, latency 25 ms, no "memory pressure"
  evictions: the slow-GPU state did not reproduce. But the hog's pages were a constant fill (the compressor
  folds them for free: swap stayed 0). memtest2 repeats it with incompressible pages touched continuously
  (22 GiB, after the long match and the heavy-phase run).
- 07:55 longmatch (10 min, BB_DEFER_CS=64 with the RasterScaling condition): MATCH_OK, 55.1 avg over 188 samples
  (cutscenes 44 fps at 870 draws / GPU 14.5 ms, open play 60), visuals correct through a goal and the replay
  (0-1 at 37:00), no [BCSKIP] in 10 minutes. Deferral now runs but barely: 1-3 dispatches/frame deferred and 2 of
  3 flushed by a conflict, far from the ~100 small dispatches a frame. The library now logs each conflict
  (BB_DEFER_CS_LOG: site bind/order/upload/readback/image-refresh/dma, the ranges that met); the soak runs carry
  it. Hitch windows (FSTAT >50 ms frames): 188 of 397 2-s windows in the long match vs 22-31 of 127-144 in the
  2-minute runs (the long match spans replays, celebrations and kit loads).
- 08:08 heavyprof (BB_MIDFRAME_FLUSH_MS=0, BB_DEFER_CS=64): MATCH_OK 52.1 avg (cutscene 43.8 fps, 877 draws, GPU
  13.7 ms). Deferral works for cs 513b88d5 (2x1x1, 51/frame, "deferred" in the profile) but its partner
  cs 87cfc5cc (4x1x1, 51/frame) was flushed by the next dispatch's BindResources conflict check (it reads what
  the previous wrote): each pair still split the pass. Fix: a compute pipeline no longer runs that check
  (deferred, it is appended after the pending ones in order; not deferred, DispatchRecord's EndRendering runs
  them first; its uploads over their ranges are still caught in the caches). GPU profile: even without the
  mid-frame flush "(after a submission, unmarked)" holds 9.5-12.9 ms/frame: the game's own submissions cut the
  open segment; the scheduler now resumes the open label after a submission (profiler Current/Resume).
  Per-pass cost in the heavy phase will be readable in the soak runs' profiles.
- 08:14 memtest2 (22 GiB incompressible hog): the host died at boot: "GPU stopped making progress (2096 ms)" ->
  the GPU watchdog (BB_GPU_WATCHDOG_MS=2000) exited the host (status 75), the emulator followed. So the
  slow-GPU state is the GPU itself slowing under system memory pressure (its memory paged), and when it drops
  below one tick per 2 s the watchdog turns it into a crash. run.sh (dev and app) now defaults the watchdog to
  5000 ms (a real hang still exits; a paging GPU gets room). Next: a memory-pressure source in the host
  (dispatch memory-pressure events) that logs the state and tightens the texture cache's eviction marks, and
  memtest3 at 14 GiB (the user's level) after the soak.
- 08:16 soak1 (chained deferral, conflict log): 298 "order" conflicts in one match window: the deferred tiny
  dispatch's write (e.g. 0x440d14300, 6.6 KB) meets the NEXT draw's vertex/index read range. The game generates
  vertices in compute right before drawing them (skinning), so deferring to the pass end can never apply to
  these. New approach, modelled on the upload hoisting: TryHoistDispatch records a small, buffer-only dispatch
  into the ahead (upload) encoder, which runs before the whole submission, when none of its ranges is touched by
  a command not yet complete (Runtime::AheadSafe = IsBufferAccessed empty apart from earlier ahead work; writes
  only into the arena) and nothing deferred meets them. Its accesses are marked EncoderAhead, so the next draw
  waits on the uploads' fence inside the open pass instead of splitting it. BB_HOIST_CS=<max groups> (64; 0 off),
  BB_DEFER_CS_LOG prints "[HOIST] ... not hoisted: <why>". Frame stats: "dispatches hoisted N, deferred M".
- 08:24 soak3 (chained deferral build): MATCH_OK 56.1; in the match 12 deferred/frame with 0 conflicts in open
  play, up to 106/frame in cutscenes (2.8 conflicts): the chains work (profile: cs 87cfc5cc and 513b88d5 "deferred",
  27/frame each, segments 0.47/0.29 ms vs 1.3/0.8 before). What the profile also shows: open play's GPU span is
  18 ms for 8.7 ms of busy command buffers: the GPU waits for the host between the game's submissions. In
  cutscenes (800-1150 draws) the GPU thread is 65-73% busy at 10-13 us/draw: those phases are as CPU-bound on
  the host's command thread as GPU-bound. Next lever there: the draw pipeline (BB_DRAW_PIPE=1, stage-B
  recording thread, off for FIFA so far) - queued as an A/B after the pressure run, then a final-defaults run.
- 08:29 soak4 (hoisting build): MATCH_OK; 28-57 dispatches hoisted per frame, 1 deferred, 0 conflicts. Cutscene
  GPU busy 13.7 ms at 889 draws (ctrl 16.2 at 892): ~2.5 ms of GPU per heavy frame saved, but the frame rate there
  (44-45) and the open-play us/draw (15-20 vs 12-13) say the command thread paid for it: the hoisted dispatch was
  recorded on the command thread itself (BindStage + dispatch into the ahead encoder). Now recorded by the
  recording thread (a scheduler command that takes the upload lock), with the ranges noted as used by the
  submission so a later hoisted upload cannot overtake it in the ahead stream.
- 08:15-08:44 soak (6 matches, deferral/hoisting builds as they came): all MATCH_OK, no stall, no deadlock, no
  sample taken (the frozen-picture sampler never fired). soak5/6 (hoisting on the recording thread not yet: that
  build landed at 08:41): 59.4 / 57.5 avg, latency 22.9 / 26.4 ms, 49-51 hoisted + 2-4 deferred per frame,
  <1 conflict. Together with the morning's runs that is 17 match loads without the rare match-load deadlock; the
  harness now samples both processes if a picture freezes, so the next occurrence will carry a stack.
- Block shadow mips: no [BCSKIP] (mip-level storage view of a block-compressed image) in any run today, including
  the 10-minute match with a goal replay; the "flat brown shells" path was not exercised. The log stays (BB_BCVIEW_LOG)
  and the fix waits for a capture; nothing changed blind.
- 08:43 memtest3 (14 GiB incompressible hog touched continuously, the user's "24 of 32 GB" level): MATCH_OK 55.2,
  open play 60 fps GPU 8-10 ms, cutscene 42-46 at 913 draws / 13.7 ms, no swap, no memory-pressure event from the
  system: at this level macOS does not page the GPU process. The slow-GPU state needs real swapping (the user's
  sessions had 8.6 GB swapped); memtest2 showed the end of that road (GPU ticks over 2 s -> watchdog exit). In
  place now: watchdog 5 s, the pressure watcher (logs the level, tightens texture eviction).
- 08:47 drawpipe (BB_DRAW_PIPE=1): the picture froze at the title screen (2 s frames, 4 draws/frame) and the
  harness stopped it: the stage-B draw pipeline is not usable for FIFA (that is why run.sh keeps it off); the
  samples are in the run folder. Off stays the default; the command-thread cost in cutscenes remains the limit
  there (10-13 us/draw at 900-1150 draws).
- 08:50 final1 (defaults: hoisting on the recording thread, chained deferral, direct read-back, watchdog 5 s):
  MATCH_OK 55.1 avg, 49-72 hoisted + 2-15 deferred per frame, <1 conflict; open play 59 fps / GPU 8.2-10.6 ms,
  latency 24.9 ms; cutscenes 45-50 fps at 824-836 draws with GPU 14.2-14.5 ms (ctrl: 16.2 at 892) and the
  command thread 70-75% busy. Hitch windows 40 of 133 (ctrl 22-31 of 127-144): an A/B without the profiler,
  twice each way (hoistoff1/hoiston1/hoistoff2/hoiston2), decides whether hoisting ships on by default.
  memory_pressure -S (simulated levels) needs root on this Mac: the watcher's event path is untested; the
  real-pressure path (memtest2) is what it was written for.
- host_app/"F16 GPU.app" refreshed with the rebuilt hosts (spin gate) and re-signed.
- 08:57-09:24 hoisting A/B (no profiler, twice each): hoistoff 59.9/59.9 avg, hoiston 59.0/59.0 (OCR samples; the
  on runs sampled 20 windows incl. more cutscene time). Hitch windows 24/111, 25/120 (off) vs 27/133, 23/133 (on):
  equal. Heavy windows (>=700 draws): off 52-58 fps at GPU 14.8-16.1 ms; on 50-59 fps at 11.3-15.4 ms, the second
  on-run 57-59 fps at 12.3-13.5 ms. Open play GPU 6.6-10 ms on vs 7-10.4 off. Hoisting (77-87 dispatches/frame)
  ships on by default; the cutscene limit is now the command thread (65-75% busy at 800-1150 draws).
- 09:15 v0.5.1 candidate (app/make_perf_app.sh 0.5.1 -> app/out_perf/F16.app + F16-macOS-0.5.1.zip, 97 MB: v0.5.0
  with the rebuilt libbbgpu arm64 + x86, libbbhost, the three hosts, run.sh and Resources/shader_seed; emulator,
  launcher, engine unchanged). Validated in the isolated data_test folder with the cache deleted first: MATCH_OK
  59.6 avg, "Shader cache: seeded 1649 files (30.8 MB)", 0 shader/pipeline compiles in all 44 stat windows,
  "relay spin window 0 us (8 processors)". Nothing committed: bloodborne_mac_port has 15 modified files
  (CHANGES-FIFA.md updated); ~/fifa_metal run.sh, app/run.sh, make_app.sh, make_host26_app.sh,
  make_shader_seed.sh (new), make_perf_app.sh (new), shader_seed/ (new), host_app refreshed; ~/fifa_autotest.sh
  (backup .bak_20261109), ~/fifa_autotest2.sh (new), app/work26/autotest_app.sh; the tools repo (metal/) needs the
  copies.

## 2026-11-09 — where the open items stand after this session
- Prebuilt shader cache: DONE (seed in the bundle, first run compiles nothing).
- Relay spin: DONE (0 us on <= 8 cores, A/B neutral).
- 120 fps: NOT POSSIBLE in the renderer (simulation stepped per vblank: 1.9x game speed at 120 Hz); 60 stays.
- Direct read-back queue: DONE (day match verified, default BB_RB_DIRECT=2).
- Tiny-dispatch encoder splits: DONE differently than planned: the game generates vertices in compute right before
  drawing, so the dispatches are hoisted ahead of the submission (77-87/frame), the rest chained to the pass end;
  heavy-frame GPU 11-13.5 ms instead of 15-16. The cutscene limit is now the host command thread (the stage-B draw
  pipeline stalls FIFA at the title: off).
- Slow-GPU state: mechanism found (system paging makes GPU ticks take seconds; the 2 s watchdog then exits the
  host). Mitigated: watchdog 5 s, memory-pressure watcher + earlier eviction. Not reproducible below real swapping.
- Match-load deadlock: not reproduced in 21 match loads; the harness now samples both processes on a frozen picture.
- Block-shadow mips / brown stadium shells: not exercised in any run (no mip-level BC storage view seen); unchanged.
- Display refresh fallback: moot in split mode (the host's SDL is initialised; only BB_VBLANK_HZ=0 uses it).
- Still CPU-bound in cutscenes (800-1150 draws at 10-13 us/draw on the command thread): the next lever would be
  cheaper per-draw binding on the host (memoized texture sets already exist) or a working draw pipeline.

## 2026-11-09 — 0.5.1-b round (user away; 0.5.1 kept as is)
- 09:3x mid-frame flush A/B (base 3 ms, 1 ms, off, base again): no difference (hitch windows 24/134, 29/137, 25/133,
  23/126; heavy phases 42-59 fps at 11.6-16 ms GPU in all four; open play 60). BB_MIDFRAME_FLUSH_MS stays 3.
- Open-play command-thread samples: 99% idle (the thread waits for the game's submits at 60 fps); the per-draw
  cost only matters in cutscenes, so the heavy-phase sampler (cutsample.sh) triggers on >= 700 draws/frame.
- 09:50-11:22 the measurement queue was stuck: chainb2/3/4 each waited with `pgrep -f chainbN.sh`, and the pattern
  also matched the text of the other waiters' own command lines (the shell wrapper carries the script source), so
  after the baseline run nothing started for 90 min. Replaced by one sequential queue (chainc.sh), a queue guard
  (qguard.sh: kills an autotest older than 1100 s, an emulator/host with no driver for 120 s, and a run whose
  results file is idle for 480 s; logs GUARD lines) and a bounded runner (runq3.sh: wait capped at 1500 s, per-run
  kill timer). Rule: chain on a pid (`kill -0`) or a lock file, never on a pgrep of a script name.
- 11:22 imghoist (image-binding dispatch hoisting, link9): MATCH_OK 59.5, hoisted 64-88/frame (base 46-49), deferred
  4-20, 0.1-0.2 conflicts, no Metal errors, picture correct. GPU busy by draws/frame identical to base_b2 (200-300
  draws 8.8-9.0 ms, 800 draws 13.2-13.4 ms, 1300-1400 draws 14.7-15.0 ms): correct and harmless, no measurable gain.
  Profile: the largest remaining in-pass split is dispatch cs 510f1e38, 240x135x1 groups, 14.5/frame, 3.95 ms/frame of
  segment time for 1.89 ms of encoder time, declined "size" (367 of 400 logged declines). Queued bighoist
  (BB_HOIST_CS=1e8) to learn whether the image/buffer rules allow it or it reads the pass.
- 11:37 bighoist (BB_HOIST_CS=1e8): MATCH_OK 59.4, hoisted 52-70/frame; the 240x135x1 dispatch is declined "colour
  attachment" (367/367): it binds the open pass's own colour target, so the split is the game's design (a compute pass
  over the frame 11-14 times per frame, ~0.5 ms of bubble each on TBDR). Not fixable from the renderer; cap stays 64.
- 11:34 drawpipe2 (BB_DRAW_PIPE=1): STALL at the title after 48 s (30-93 draws/frame at 45-60 fps before, worst
  frames 134-1214 ms). Host: every thread parked (command thread in Process's wait, recorder in its cv wait with the
  queue predicate, draw pipe threads idle). Game (eboot at 0x400000000, shadps4 at 0x700000000000): Game:Main in game
  code with sceKernelNanosleep (a polling loop), job threads polling, the rest in semaphores/cond waits. So the game
  polls a value the host never produces (a label or the flip status) and submits nothing more. Added a stall dump
  (BB_STALL_DUMP_S, default 8: [STALL] lines with the pending fences, their current values and pipe positions, the
  recorder queue and the deferred signals; bbgpu.cpp WatchStalls) and queued drawpipe3 to read it.
- Command-thread cost found in the base_b1 sample (open play, 45% busy): 11% of the thread in the page-protection
  round trip (host -> game's bb:GpuProtect thread -> host, ~0.1-0.2 ms each, two thread wake-ups: the host's wait
  spins only ~2 us) under SynchronizeMemory uploads, QueueReadback/ProtectForCpuRead and UpdateImage; 4% in
  HasOndemandIn (texture-cache mutex per ObtainBuffer); 5% PM4 decode. Added "Protects: N per frame, ms per frame"
  to the frame stats and BB_PROTECT_SPIN_US (host_runtime.c; default 0 until the A/B: heavycpu2 vs heavycpu3=200).
- 11:40 heavycpu2 (new "Protects:" line, no spin): 80-98 page-protection round trips per frame costing 1.5-2.8 ms
  per frame in open play and 5.3-9.1 ms per frame in cutscenes (1200-1270 draws) on the command thread. That is
  the largest CPU cost found in the port (half the cutscene frame budget). Fixes in flight for 0.5.1-b:
  (a) ProtectForCpuRead (texture_cache.cpp) issued one page-manager call per 4 KiB page: now one per contiguous
  run of pages whose count crosses zero; (b) HasOndemandIn answers without the texture-cache mutex when no
  on-demand image exists (atomic ondemand_any); (c) BB_PROTECT_SPIN_US spins both ends of the round trip (the host's
  wait in host_runtime.c, the game's bb:GpuProtect ring peek via the shared block's protect_spin_ns, formerly pad3)
  before sleeping; default decided by the A/B heavycpu4 (0) vs heavycpu3b (200) on the new libraries.
- 11:48 heavycpu3 EXITED in boot: the host aborted in the handshake because a build was relinking
  out/gpu-arm64/libbbgpu.dylib (the host loads it from the build output) at that moment. Rule: builds take
  $S/build.lock; runq3 waits for it before launching. The sampler (cutsample2.sh) also waited forever for a match
  that never came and blocked the chain behind it: now bounded; qguard2.sh kills a sampler without a run (300 s).
- 11:57 heavycpu4 (coalesced read watchers, lock-free HasOndemandIn, spin 0): protects 38-50/frame at 0.75-1.1 ms
  in open play, 48-57/frame at 0.9-1.3 ms at 700-1475 draws (heavycpu2: 80-98 at 1.5-2.8 and 5-9 ms); command
  thread 8-11.5 us/draw in heavy frames (was 13-15). 60 fps, worst frames 27-29 ms in open play.
- 12:00 heavycpu3b (same + BB_PROTECT_SPIN_US=200 both ends): per-protect latency halves (open play 17-40 protects
  at 0.15-0.6 ms/frame) but open play ran at 54-56 fps with 51-59 ms worst frames: the spinning game-side protect
  thread takes a core from the game on this 8-core Mac. Default: spin only above 8 cores (100 us), like the relay.
  The heavy samples (772-839 draws, the readback phase) still show 14% of the command thread in protect waits
  under ForEachUploadRange (one waited round trip per region) and 8% in Scheduler::Finish for buffer downloads.
- 12:15 batched protect waits: ForEachUploadRange posts every region's protect and waits once before the copies
  (memory_tracker.h -> Core::ProtectBatch -> host_runtime.c runtime_memory_gpu_protect_batch, weak-imported so
  the game-side library needs nothing). Safe because the copies (on_upload) already ran after the whole loop: a
  guest write between a post and its application is included in the copy, a write after the wait faults.
  Validation run "batchprot" queued behind drawpipe4.
- 12:07 drawpipe4 dump (flip state + newest fences): flips done 1245 with 0 pending and empty request/swap queues,
  deferred signals 11821/11821, recorder and pipe idle, "rendering 0"; the game submitted nothing for 8 s. The
  newest fence (position 87704320, reached) expects 0xc039100000000001 as 8 bytes and the memory holds 0x1: the
  upper dword looks like the following packet's PM4 header, i.e. a 32-bit label parsed as 64-bit, or the write
  landed as 4 bytes. Whatever the game polls is not in the pending-fence list and not a flip. The draw pipe stays
  off (BB_DRAW_PIPE=0); the [STALL] dump (BB_STALL_DUMP_S) remains in the build for the next attempt. Bounded
  attempt closed here (3 captures).
- 12:11 batchprot2 (batched protect waits, spin 0, new libraries): MATCH_OK 59.0, open play 60 fps with 25-32 ms
  worst frames (one 45.6); protects 17-47/frame in open play at 0.06-0.36 ms/frame, 57-80/frame at 0.37-0.44 ms
  in cutscenes (1043-1209 draws, 8.6-9.0 us/draw against 13-15 at the start of the day); heavy samples: the
  remaining wait is the one batched round trip per upload (8-11% of the thread at 760-880 draws), PM4 decode 7%,
  submit-queue mutex 5%. No Metal errors. The next lever would be one wait per draw (defer every binding's
  on_upload to the end of BindResources) and the submit-queue mutex.
- 12:18 packaged 0.5.1-b: OUT=app/out_perf_b bash app/make_perf_app.sh 0.5.1-b -> app/out_perf_b/F16.app +
  F16-macOS-0.5.1-b.zip (97 MB); 0.5.1 in app/out_perf untouched. Contents against 0.5.1: image-binding dispatch
  hoisting, coalesced read-watcher protects, lock-free HasOndemandIn, batched protect waits, BB_PROTECT_SPIN_US
  (default 100 us above 8 cores, else 0), "Protects:" frame-stats line, [STALL] dump (BB_STALL_DUMP_S, default 8).
  Nothing committed (SOURCES.txt's tag line is aspirational until the commits land).
- 12:19 first app-harness validation of 0.5.1-b EXITED at match load: the queue guard (qguard2) saw an emulator
  with no "fifa_autotest2.sh drive" process (the app harness's driver is autotest_app.sh) and killed it as an
  orphan after 120 s. qguard3 recognises both drivers; validation rerun at 12:24. Harness note: the guard's driver
  patterns must list every harness that launches the emulator.
- 12:24 app-harness validation of 0.5.1-b (fresh seeded cache): MATCH_OK 59.5, 0 compiles, no errors; open play
  38-50 protects/frame at 0.7-1.2 ms (the batched wait is now timed too; the thread is 60% idle there, the gain
  is in the heavy phases). Copied to /Volumes/SanDiskSSD as "FIFA 16 v0.5.1-b.app" + F16-macOS-0.5.1-b.zip, next to
  v0.5.1. Both untested by the user; nothing committed. Queue guard (qguard3.sh), build lock and bounded sampler
  live in the session scratchpad; the tools repo still needs copies of the harness scripts.

## 2026-11-09 — 0.5.1-c round ("take it to the max": every remaining command-thread lever, no confirmations)

- 17:10 Heavy-phase sample of 0.5.1-b (batchprot2, cutscene, 2491 samples): protect round-trip waits still 8.8% (ulock under
  SynchronizeMemory), the command loop's queue mutex lock/unlock 12.6% + ProcessCommands 2.8% = the WaitRegMem yield-spin,
  _tlv_get_addr 5.8% (thread_local reads under every binding: Shader::Info::Snapshot via UserData), HasOndemandIn 1.8%,
  PM4 decode 7%, BufferBarriers::Mark 2.6%, NoteSubmissionUse 2.6%, ReadbackWait 2%.
- 17:07 spinprof run (BB_SPIN_PROF=1, 0.5.1-b): [SPIN] wrm-yield 9-20% at 4100-7700 waits/s = 70-130 WaitRegMem a frame that
  are not met at first test; wrm-inpend 0 because without the draw pipe the EOP fences the recorder writes
  (SignalAfterHostCopies) were never listed as pending, so the command thread spun until the recorder caught up.
  MATCH_OK 60 fps, p99 22-28 ms, Protects 37-61/frame at 0.7-1.5 ms.
- 17:20 Experiment (scratchpad tfp/): an arm64 helper can task_for_pid a Rosetta x86_64 process and mach_vm_protect its pages
  when the TARGET is ad-hoc signed with com.apple.security.get-task-allow (no entitlement needed on the caller; the caller's
  cs.debugger entitlement alone prompts for authorisation). The target faults on the next write as with mprotect.
- 17:45 Built 0.5.1-c candidate 1:
  * direct page protection (host_runtime.c host_protect_direct_init/protect_direct, main.c, host.h, bbgpu_shared.h tail
    fields protect_direct/protect_lock/page_kind_addr/bytes, bbport_split.cpp SharedProtectGuard + mmap'd kind table):
    the host changes the game's page protection itself (one mach_vm_protect per view, ~µs) instead of the ring relay
    (~80 µs, two wake-ups); the game's fault handler and the host order through the shared spinlock; BB_PROTECT_DIRECT=0
    or an emulator without get-task-allow → relay as 0.5.1-b. Harness emulator re-signed (backup .unsigned_bak);
    make_perf_app.sh signs the bundled emulator with the entitlement.
  * pending recorder fences (liverpool.cpp RecorderFenceDeferred): EOP fences deferred to the recorder are listed as
    pending without the draw pipe too, so WaitRegMem is answered from the list; BB_PENDING_RECORDER_FENCES=0 restores.
  * Shader::Info::snapshots_in_use fast path (no thread-local reads until the draw pipe installs snapshots).
  * TextureCache on-demand 4 MiB chunk bitmap pre-check before the mutex.
  * [SPIN] by_addr now counts memory WaitRegMem addresses (kind 1).
  First build failed on pid_t in host.h (int now); chain restarted with the rebuilt hosts.
- 17:31 direct1 (lib-side changes only: the harness host bundle still had the 0.5.1-b hosts, so protection relayed):
  MATCH_OK 60 fps, p99 20-29 ms; [SPIN] wrm-yield 0.0% (0/s) against 9-20% at 4100-7700/s in spinprof: the pending
  recorder fences remove the command thread's wait-spin entirely. Protects 30-40/frame at 0.9-1.1 ms (relay).
- 17:32 direct2 EXITED in boot: the host hung in task_for_pid behind the "Developer Tools Access" dialog my entitlement
  test (case D, debugger-entitled caller on a plain target) had left open; taskgated queues requests behind a pending
  dialog. Dismissed the dialog (osascript Escape to SecurityAgent); task_for_pid now runs on a thread with a 1.5 s
  limit (relay mode on timeout). Re-verified: entitled target + plain caller answers at once, no dialog.
- 17:40 direct2b: host logs "direct page protection: the host changes the game's page protection itself (task port)".
- 17:46 direct2b (direct protection + all lib changes): MATCH_OK, 60 fps, p99 22-30 ms, rendering correct (replay shot
  checked). Protects 37-52/frame at 0.5-0.8 ms (≈12 µs each: one cross-task mach_vm_protect incl. TLB shootdown, no
  wake-ups; relay was ≈27 µs each). [SPIN] 0%. Command thread at 350-450 draws/frame: 8.7-9.8 µs/draw against
  11.5-12.9 in spinprof (0.5.1-b) — about 25% less per draw. Packaged as app/out_perf_c (F16-macOS-0.5.1-c.zip, 97 MB,
  emulator signed with get-task-allow, "emulator: get-task-allow kept"). direct3 (heavy-phase sampler at >= 500
  draws) and the app-harness validation (appval_c.log) queued.
- 17:47 direct3 (heavy sampler at >= 500 draws, 3 samples at 533/687/894 draws): MATCH_OK. At 894-899 draws/frame the
  command thread is 8.0-8.4 µs/draw and 27-45% idle (0.5.1-b: 10.2-10.4 µs/draw, 28% idle) while GPU busy is
  13.5 ms/frame (74-77%): the GPU, not the command thread, limits cutscenes now (54-58 fps there, worst 39 ms).
  Remaining command-thread self time: cvwait idle 34%, ReadbackWait 6% (cutscene CPU readbacks), PendingFenceValue 3.7%
  (list grew to the 4096 cap: labels the game rewrites never "hold" their value), WaitHostCopies yield-spin 3%
  (EOS/WriteData ordering), RunDmaData memmove 3%, _tlv_get_addr 2.6% (Regs() via stage_regs, ChunkUser, on_helper),
  BufferBarriers::Mark 1.9%, getenv("BB_BCVIEW_LOG") per draw 0.9%, mach_vm_protect 1.1%.
  Threads in that phase: GpuCommandProcessor 58% busy, MtlRecorder 39%, DrawPrep0 22%.
- 17:55 Batch 2 edits (not yet built): pending fences pruned by the recorder's deferred-signal counters (PendingFence
  signal_seq; Scheduler/Rasterizer DeferredSignalsIssued/Done), BB_BCVIEW_LOG cached, Rasterizer::Regs()/CbExtent/
  CsRegs/DbExtent skip the thread-local until the draw pipe installs stage registers (stage_regs_used).
- 17:58 appval_c (packaged candidate 1, fresh seeded cache, direct protection confirmed in its log): MATCH_OK, 60 fps,
  p99 21-30 ms, 0 compiles, no errors. Copied to /Volumes/SanDiskSSD as "FIFA 16 v0.5.1-c.app" + zip (to be refreshed
  with candidate 2 if direct4 and its validation pass). Batch 2 built; direct4 running with BB_GPU_PROFILE=1.
- 18:02 direct4 (batch 2, BB_GPU_PROFILE=1): MATCH_OK; the profiler itself costs hitches (p99 50-60 ms) — direct5 without it:
  MATCH_OK, heavy phase 55-57 fps at 887-898 draws, GPU busy 13.4 ms, open play 60 fps p99 26-28, command thread 7.2-7.4
  µs/draw, 50-55% idle. Batch 2 verified in the sample (PendingFenceValue and the per-draw getenv gone).
  GPU profile (cutscene, per frame): dispatch cs 510f1e38 (240x135 groups) x13 = 8.0 ms segment / 6.2 ms encoder
  (0.47 ms each: a full-screen copy as compute, plus 13 pass splits); main 1080p pass 3.7 ms; 1x1x1 dispatches
  3327c37b x5 (1.9 ms segments) and 3ba88f63 x13 (0.65 ms). The copy shader (SPIR-V in the seed): one
  ImageSampleExplicitLod at ((gid+0.5)*buf[0..1]) LOD 0, one ImageWrite at gid, output = sample.zyxw, optional
  depth remap (backend). 
- 18:20 Batch 3 (built): copy dispatch as a fragment pass. CopyDispatchDetectPass (shader_recompiler/ir/passes/
  copy_dispatch_detect_pass.cpp, after CollectShaderInfoPass) matches that shape generically and records it in
  InfoPersistent::CopyDispatch (ShaderMetaVersionBase 11 -> 12: the cache and the bundled seed recompile once);
  Rasterizer::PlanCopyDispatchPass (dst 2D colour, grid*workgroup == size, scale from the V# in guest memory, remap
  bit from push_data) + BlitHelper::CopyDispatch (copy_dispatch_fs: sample at position*scale, remap, swizzle; clear +
  store, no load). BB_COPY_CS_PASS=0 / BB_COPY_CS_DETECT=0 disable, BB_COPY_CS_LOG=1 logs. Stats: "%.1f drawn as
  copy passes" in the Frame timeline line. Running direct6 (log + profiler) to confirm detection and the GPU gain.
- 18:30 direct6 (batch 3, BB_COPY_CS_LOG=1 + profiler): MATCH_OK, no Metal errors, picture correct in the harness.
  CopyDispatchDetectPass finds 510f1e38 ("img1 <- img0 (sampler 0), scale buffer 0 dwords 0/1, workgroup 8x8,
  swizzle 2103"); but only 1.0 of the ~13 instances a frame ran as a pass — the other 12 declined (the 200-line
  log was used up by the mip-chain dispatches, correctly declined as "same image"). Decline log now prints only
  grids >= 256 groups with image ids, destination size/type/format; direct7 running for the reasons.
- 18:55 direct9 (copies allowed between two views of one image, size from the view): MATCH_OK, picture correct
  (open play shot checked), 4.0 copy passes a frame in every phase, no declines logged for the 240x135 grid, yet
  the profile (direct10, run end) still shows 12 encoders a frame under the 510f1e38 label (4 of them the passes,
  which took the dispatch's label). Heavy phase 51-57 fps at 903-927 draws, GPU busy 13.3-16.4 (direct5 13.4 at
  887-898: not better yet). Open play p99 20-23 ms (was 26-28). Next build: passes get their own profile label and
  a log line when a large dispatch's shader info carries no detection (the only silent path left) - direct11.
- 19:07 direct11 (passes with their own profile label): MATCH_OK. The label "copy pass cs 510f1e38" carries 8-12
  encoders a frame for 4.0 passes a frame: the profiler charges the encoders that follow a mark (the resumed main
  pass after each split) to the copy's label. So the "8 ms copy dispatch" of the morning profile was mostly the
  main pass continuing after the split, not the copy; there are 4 copies a frame, all converted now, and the GPU
  cost that remains is the 4 attachment store/load splits the copy's read of the colour target forces (inherent).
  Deciding the default by an A/B without the profiler: direct12 (passes on) vs direct13 (BB_COPY_CS_PASS=0).
- 19:20 A/B (no profiler): copy passes on (direct12) mean p99 18.7 ms over 124 samples, GPU busy 8.3-9.6 ms at 330-500
  draws, worst 25-33 (two 43s); off (direct13, BB_COPY_CS_PASS=0) mean p99 21.0, GPU 8.6-10.6 at 400-440 draws, worst
  frames 57-62 in its heavy window. Equal or better on: copy passes stay ON by default. Final build + seed refresh
  (harness cache merged into app/shader_seed, backup shader_seed/CUSA02138.bak_20261109) + candidate 2 package.
- 19:26 appval_c2 (candidate 2 = final 0.5.1-c, fresh seeded cache): MATCH_OK, direct protection on, 4 copy passes a
  frame, 2 compiles (the refreshed seed preloads 259 of 372 pipelines: 113 entries the harness flow did not touch
  today keep the old metadata and compile on first use), no errors. Copied over the SSD candidate 1 ("FIFA 16
  v0.5.1-c.app" + F16-macOS-0.5.1-c.zip). 0.5.1 and 0.5.1-b untouched; nothing committed.
  Left open: the 113 stale seed entries (a content sweep would refresh them); the GPU-bound cutscenes (13.5 ms GPU
  busy at ~890 draws: 4 inherent pass splits for the colour-target copies, the 1x1x1 dispatches 3327c37b/3ba88f63
  that still split passes, ~1.9+0.65 ms of segments); the 100 ms phase-transition hitch seen once per match.

## 2026-11-09 — 0.5.1-d round (hitch, seed, pass splits, hardening)

- 19:35 The in-match 100-180 ms frames (one or two per match): the spike log shows the GAME not flipping for that long
  (game 180 ms apart) while the host's stages are small (host->flip 2-5 ms, GPU thread 2 ms, 0-14 page faults
  waited <1 ms), each next to [Kernel.Fs] opens of commentary/speech banks (/download0/audiodata/... missing, the
  game then loads them from the disc). Emulator-side file loading, not the renderer: documented, not fixable here
  (no emulator code changes in these bundles).
- 19:36 Hardening: the game's fault handler gives up on the shared protection lock after 1 s with the host alive
  (handles the fault without it, says so) instead of spinning on a stuck host. d1 running with BB_DEFER_CS_LOG=1
  for the 1x1x1 dispatches' decline reasons.
- 19:45 d1 (BB_DEFER_CS_LOG=1): MATCH_OK; the 400-line decline log was again filled at boot by grids over the cap
  (510f1e38 "size" x365) — the in-match reasons for 3327c37b/3ba88f63 (1x1x1) did not fit. Visible: deferred
  dispatches flushed by draws binding a 192 MiB read range (0x442a6e000+0xc000100) that covers a deferred write
  (172 + 80 such conflicts a run). Hoist/defer decline logs now skip grids over the cap (build after dseed).
  dseed (10-minute match) running to widen the seed.
- 19:57 dseed (SAMPLE_SECS=600): 0 compiles over 8 minutes of match (170 fps samples, mean p99 24.7 ms) before the
  guard's 480 s idle rule killed it (the harness writes its report late): the seed already covers everything this
  flow reaches; the 113 stale entries are content outside it. Guard idle limit raised to 1000 s (qguard4.sh).
- 20:04 d2 (hardened build, filtered decline logs): MATCH_OK. The 1x1x1 dispatches 3327c37b/2eaab068 are declined
  as "no open pass" 198-199 times each: they arrive between passes and split nothing; their profile "segment" time
  is GPU idle before them (the GPU waiting for the command stream), not a split. Deferred-dispatch flushes by
  ordering requests: 299 a run (~0.1 a frame), negligible. No renderer lever left in the pass structure: the four
  colour-target copies are the only splits and they are the game's design.
- 20:05 0.5.1-d = 0.5.1-c + fault-handler lock timeout (1 s, then handle without the lock) + decline logs limited
  to grids within the cap; same renderer defaults. Packaging app/out_perf_d, validating, then SSD.
- 20:09 appval_d (packaged 0.5.1-d, fresh seeded cache): MATCH_OK, 0 compiles, direct protection on, no errors.
  Copied to /Volumes/SanDiskSSD as "FIFA 16 v0.5.1-d.app" + F16-macOS-0.5.1-d.zip beside 0.5.1, 0.5.1-b, 0.5.1-c.
  Nothing committed. What remains is outside the renderer: the game's audio-bank loads (100-180 ms frames at
  commentary events), the per-vblank simulation (60 fps ceiling), the four colour-target copy splits, and the
  113 seed entries for content the match flow never reaches.

## 2026-11-09 — 0.5.1-e round (jagged lines: anti-aliasing)
- 20:30 Facts: the window is the full Retina screen (3024x1834 px, density 2); the game renders 1920x1080 with 2-sample
  MSAA (EQAA 4 coverage / 2 fragments on the PS4 — Metal has no EQAA, so edges get 2 samples where the PS4 had 4);
  the presenter scales 1080p -> 3024x1834 with a linear sampler; FSR (EASU/RCAS, host pass) exists but is off in the
  config; no post AA pass exists.
- 20:52 fsr1 (config fsr_enabled, RCAS off): MATCH_OK, GPU busy unchanged (13.6 in cutscenes), mean p99 19.7: free, but
  the zoomed crops show the same staircase on the pitch lines as bilinear — the aliasing is in the 1080p render.
- 20:55 BB_MSAA=<n> (video_core/bb_msaa.h, applied in image_info.cpp and the pipeline key): multisampled guest targets
  get n real samples; FIFA's EQAA resolve walks coverage samples 0-3 through the emulated FMASK, so 4 real samples
  are true 4x. msaa4 run started (FSR off).
- 21:00 msaa4 (BB_MSAA=4): MATCH_OK, brightness unchanged (median frame luma 0.354 vs 0.350), open play 60 fps p99 20,
  but cutscenes 47-52 fps at GPU busy 16.5-18.9 ms (+5 ms) — and the zoomed centre-circle crop shows the SAME
  staircase as 2x. Cause found in the FMASK emulation: FIFA's resolve decodes 2-bit fields (Fmask8_S4_F2) and the
  constant 0x76543210 reads as coverage->fragment (0, 0, 1, 0): three of four taps take fragment 0, i.e. no
  anti-aliasing at all since the port began (the user's jagged lines). resource_patching_pass.cpp now builds the
  word per FMASK format: coverage sample i -> colour sample i mod N (N = fragments or BB_MSAA): 0x44 for 2
  samples (true 2x), 0xE4 with BB_MSAA=4 (true 4x). ShaderMetaVersionBase 13 (resolve recompiles). Runs fm2/fm4.
- 21:22 fm2c (resolve word 0x44 = (0,1,0,1), 2 samples): MATCH_OK, GPU busy unchanged, p99 20.3, luma 0.368 (+5%);
  fm4c (BB_MSAA=4, all shaders recompiled with 4-sample image info): MATCH_OK but the scene renders BLACK (HUD only,
  luma 0.067) — the 4x override is not viable as is (msaa4 with cached 2-sample shaders rendered fine at +5 ms GPU).
  The fm2c crops still show hard stair-steps on the lines: the two colour samples hold the same data at edges
  (the 10-31 note saw the same). smp0/smp1 (BB_FMASK=00 / 55: sample 0 only / sample 1 only, BB_MSAA_LOG=1)
  queued to prove whether the samples ever differ and whether the scene target is swapped 1->2 samples by copies.
- 21:40 smp0/smp1 (BB_FMASK=00 / 55) were invalid: 0 compiles — the FMASK word is baked into cached SPIR-V and not
  part of any key, so both ran the cached 0x44 resolve (the 10-31 note said "with cleared shader caches" for a
  reason). MSAALOG empty: no backing swaps and no port-side resolves during a match (the scene renders 2-sample
  throughout and the game's resolve reads it). ShaderMetaVersion now carries a hash of BB_FMASK/BB_MSAA (bits 27-31)
  so such runs recompile. smp0b/smp1b queued; fixed goal-kick-camera crops of the stands will show whether the two
  colour samples differ at all (the crops of fm2c suggest they do not).
- 21:52-22:21 smp0b/smp1b + RTFMT: the scene really is 2-sample MSAA and the resolve averages both samples (the
  0x44 word is right); geometry edges ARE anti-aliased. The visible staircase on the pitch lines is texture
  content inside polygons (the line markings are texels, minified/magnified with no supersampling), which MSAA never
  touches. So: (a) the earlier claim "the FMASK fix gives visible AA on the lines" was WRONG; (b) the fix for what
  the user sees is a post-process edge AA pass.
- 22:21 build: edge AA pass (FXAA 3.11 luma variant) in the presenter, at 1080p before the scale to the screen:
  vk_presenter.cpp PrepareFrame -> pp_pass.EdgeAa -> renderer_metal/mtl_present.mm (shader in mtl_blit_shaders.h).
  Default ON. Env: BB_AA=0 off, BB_AA_SUBPIX (0.5), BB_AA_EDGE (0.125), BB_AA_EDGE_MIN (0.0312), BB_AA_SPLIT=<x
  fraction left untouched, for side-by-side crops>, BB_SNAPSHOT_TRIGGER=<file> (touch it -> lossless PNG of the drawable).
- Upstream survey (shadPS4 origin/main, 78 commits past our base 3eecea94): nothing with a measurable gain for FIFA.
  Renderer: 2831b681 already equivalent here; 914e78c3 / 145932bf / 6add101d are micro-opts on paths that are not
  our bottleneck; c6b24ec1 / 8e23388a / 1eab1796 / 99e33b7e are large Vulkan-side refactors of code this port replaced
  with the Metal path; recompiler fixes are for other games and would force a shader-cache rebuild. Emulator side:
  kernel / save_data / np / ajm / fs correctness fixes (87290181 sorted mounts, 16157ae6 VFS cache invalidation,
  a5441d6f guest init thread, 8a66adab submit-every-N-draws per game): none touches FIFA's hot paths. Not merged.
- "Convert parts of the emulator to arm64": the game's own code is x86-64 and must run under Rosetta in one process
  with the HLE libraries it calls (no cross-architecture calls inside a process); everything that could move
  (GPU command processing, shader recompiler, Metal recording) already runs natively in the arm64 GPU host. Open
  play sits at the 60 fps simulation cap. No further arm64 conversion has a measurable gain.
- 22:36 aa1 (BB_AA_SPLIT=0.5, GPU profile): lines visibly smoother on the AA half (crops/cmp3.jpg). One-off: crowd
  rendered BLACK in this run only. ctl1 (22:43, BB_AA=0), aa2 (22:47, AA on), aa3 (22:53, AA + profiler): crowd fine
  in all; contact sheet of 46 earlier runs: black crowd only in aa1. Not the AA pass, not the profiler.
- AA cost, unpaired (ctl1 vs aa2): open play GPU 9.59 vs 10.20 ms at 362 / 372 draws; cutscene 13.13 vs 15.23 ms
  (3-4 windows, noisy). The profiler cannot isolate the pass (labels are charged until the next mark).
- 23:01 build: BB_AA_QUALITY (0 = 5 search steps, 1 = 8, 2 = 12; default 2), BB_AA_ALT=<s> (measurement aid:
  cycles off/q0/q2 every s seconds, logs "[AA] off|q0|q2"), and ColorAttachment::discard -> MTLLoadActionDontCare
  for the two full-screen present passes (PostProcess to the drawable, EdgeAa to its 1080p target; both overwrite
  every pixel, Load made the GPU restore the old contents on a tile-based GPU). Run aa4 (BB_AA_ALT=15, SHAD_STUTTER=1).
- Hitches: the 100-165 ms frames coincide with bursts of failed loose-file opens on the "FileDevice driver" thread
  (hundreds per burst, ~50 us each = 22-34 ms per 500; FSNEG lines). About 10% of a burst; the rest is the game's
  own loading. An emulator-side negative cache needs a full emulator rebuild (no build tree left): recommendation.
- NEW (ctl1 Spike lines): late frames in cutscenes carry game-side GPU page-fault waits. 49 fps window at 1252
  draws: GPU 72% busy, command thread 52% idle, each late frame 5-10 relayed faults with 6-14 ms waited. Over all
  late frames with 250+ draws: 493 frames, mean 4.7 faults / 4.7 ms waited; 1250+ draws: 7.6 faults / 8.5 ms.
  A relayed fault that touches an on-demand image waits for the GPU command thread to reach its command
  (vk_rasterizer.cpp ResolveOndemandImages -> liverpool->SendCommand<true>): with 1200 draws queued that is most of a
  frame. Run flt1 (BB_FAULT_STATS=1) to name the pages.
- 23:01 aa4 (paired, BB_AA_ALT=15): clean open-play windows GPU busy: off ~9.0 ms, 5-step ~9.2 ms, 12-step ~9.0 ms;
  cutscenes at 860-950 draws: off 14.1-16.6, on 15.2-17.4 (same spread). The edge AA pass costs at most ~0.2 ms,
  inside the noise; quality level makes no measurable difference -> default stays BB_AA_QUALITY=2. Crowd fine.
- 23:11 flt1 (BB_FAULT_STATS=1, BB_AA_SPLIT=0.5): crowd fine (aa1's black crowd stays a one-off, not the split).
  ROOT CAUSE of the cutscene frame-rate loss: per 2 s "[WFAULT] n=660 ondemand=674.7ms download 52 (674.1ms)",
  "[ODWC] 93x75f109DP@458f6f600x52", "[ODT] last write pending 52 | ordered wait 52 (664.6 ms)",
  "[FAULTS] write=660 read=0 wait=701.3ms s4=52". The game writes a constant buffer 128 bytes past the end of the
  93x75 RGBA32F on-demand image at 0x458f6f600 (111600 bytes, not droppable, below the prefetch threshold), i.e. on
  the image's last page; the page is read-watched for the image, so the write relays and the host downloads the
  image synchronously. The image's last write is still in the pending command buffer, so every such fault waits
  8-13 ms for the GPU: the game thread is blocked 425-870 ms of every 2 s and the frame is serialised with the GPU
  (GPU busy ~15.1 ms, frame span ~21.5 ms, command thread ~50% idle, 49-54 fps).
  (The 2026-11-04 asynchronous-landing attempt was reverted on run 095554, later identified as the pre-existing
  night-match collapse: never validly tested.)
- 23:35 build: TAIL RELEASE (BB_ODW_TAIL=0 off). texture_cache.cpp ReleaseOndemandTails: a write fault wholly past
  the end of a pending on-demand image, on the image's last page (image has earlier pages), lifts that one page's
  read watcher (range trimmed, refcounts exact), snapshots the image's tail bytes in guest memory, keeps the image
  pending and queues an asynchronous download (tail_downloads -> ProcessDownloadImages -> DownloadImageMemory
  only_if_pending). Every asynchronous landing goes through WriteBackImage: head unconditionally, the released tail
  only while guest memory still equals the snapshot (CPU bytes written there are kept); a landing for an image that
  left the pending set is skipped. The next GPU write protects the tail again (QueueReadback ->
  ReprotectOndemandTail). A write INTO the image bytes of a released tail still downloads synchronously
  (vk_rasterizer.cpp ResolveOndemandImages: OndemandTailHit). texture_cache InvalidateMemory keeps the readback of a
  tail-released image for writes beside it. Residual risk: a CPU read of the image's last ~1.7 rows between the
  page-sharing write and the landing sees the previous frame's bytes (the CPU never reads this image: read=0);
  the GPU buffer-read path's deferred landing writes the tail unconditionally.
  Stats: [WFAULT] "tail N (ms) unresolved N", [ODTAIL] released/reprotected/landings. Run tail1.
- 23:44 tail1: no gain ("download 60 (520 ms)", "tail 0"): the page-sharing write is on the image's FIRST page
  (below 0x458f6f600), not the last. 23:45 build generalises the release to both edge pages (OndemandTail.edge[0/1],
  range.first advanced for a head release; WriteBackImage guards each released edge with its snapshot).
- 23:54 tail2 (BB_FAULT_STATS=1): "[WFAULT] ondemand=1.3ms | download 0 tail 60 (0.4ms) unresolved 0",
  "[ODTAIL] released 60 reprotected 60 | landings: tail written ~100, kept 0, skipped 0", "[FAULTS] wait=27-37ms"
  (was 700 ms per 2 s). First cutscene group at 860-900 draws: 59.0-59.6 fps (flt1: 50-57), command thread idle
  52-57%. MATCH_OK. Later cutscene group (880 draws, 51-52 fps in BOTH runs, worst frame 55-65 ms) is a different
  problem: the GAME does not submit for 45-55 ms every 12-15 frames (spike log "game 52.2!", GPU thread on CPU
  6 ms, 10 page faults 0.6 ms waited). Not the file probes (the 600 "duplicate messages" per window are the
  sceNpPartyCheckCallback stub on FEThread). Next: sample the emulator during such a window.
- 2026-11-10 00:06 stall1 / 00:20 stall2 (10-minute match) / 00:31 def1 (default settings, no fault stats): all
  MATCH_OK. The periodic game-side stall did not recur in any of them (harness/stallhelper.sh samples the emulator
  when an [FSTAT] window has >= 3 hitches at >= 45 fps with GPU >= 11 ms): OPEN, seen only in 231132 and 234559.
  def1: intro flyover 1220-1357 draws 58.2-59.0 fps (flt1: 49.9-51.8), goal-kick/crowd cameras 788-909 draws
  55.8-59.8 fps at GPU 14.7-17.4 ms (now GPU-limited), open play 59.4. stall2's slow windows are purely GPU-bound
  (GPU busy 19-23 ms, p50 20 ms, 0 hitches, 44-50 fps). Cutscene snapshots (crops/def1_sheet.jpg) correct.
  The three game gaps over 70 ms in def1 are all in the pre-kick-off asset load (kit/face/shoe opens), none in play:
  no evidence that an emulator-side negative cache for failed opens would gain anything measurable.
- 00:32 0.5.1-e packaged (app/out_perf_e, F16-macOS-0.5.1-e.zip 97 MB): build_e.sh x86 + make_perf_app.sh 0.5.1-e.
- 00:38 appval_e (packaged app out_perf_e, fresh seeded cache, run app/work26/data_test/runs/20261110_003325):
  MATCH_OK, seed 1709 files in 337 ms, direct page protection on, no errors. 575 pipeline builds from the seed over
  the whole run = 198 ms in total (0.34 ms each, cache loads). Open play 59-60 fps, 1 hitch in 20 windows;
  intro flyover 1356-1408 draws 57.8-58.9 fps, 845-863 draws 58.9-59.4 fps (GPU 14.6-14.8 ms).
- 00:39 copied to the SSD: "FIFA 16 v0.5.1-e.app" (ditto, codesign verify ok) + F16-macOS-0.5.1-e.zip (cmp identical);
  the four earlier bundles there still verify.
- Periodic stall, log analysis of 234559: stalls every 12-15 frames (46-59 ms game gap), only at 880-899 draws with
  flip_rate 1, fast cadence; host stages small in the stalled frame (host->flip 7.5 ms, queued 0, acquire 0).
  NOT a GPU threshold: other runs hold 59-60 fps with 0 hitches at GPU busy 15.2-16.2 ms. NOT the pacing's slow
  path (slow cadence completes at once). So it is something the game does in one scene type. 00:42 chainstall.sh:
  up to three more sampled runs (stall3-5) to catch it with `sample`.
- 00:58 stall3 (004136): MATCH_OK, no pattern window. stall4 (005009): MATCH_OK, ONE pattern window caught and
  sampled (results/stall4.sample1.txt, 555 samples in 4 s; the sampling itself froze the next three windows).
  Scene = the goal-kick wait camera (keeper with the ball, crowd stand behind, 876-899 draws, flip_rate 1); the
  harness never takes the kick, so the game sits in it for 12-16 s. Sample (harness/sample_leaves.py): Game:Main
  78% in game code + 11% sched-yield inside a job-wait loop (0x4024ccfb5 -> 0x400305b90 -> 0x400308c0e runs jobs
  while waiting), 90_job0..3 77-85% running jobs, the submit thread 62% game code + 7% ring push. No emulator
  wait, no file access, no fault wait. => in this scene the game itself uses ~5 cores of Rosetta-translated CPU;
  with the host's command/recording threads the six performance cores are saturated, and the stall is the game's
  own job chain running late (most likely a thread spilling to an efficiency core). Intermittent per run: tail2
  stalled in every goal-kick scene from its start, def1 / stall1-3 / appval_e never, stall4 one window.
  Nothing left to fix on the renderer side. Possible follow-up (needs an emulator rebuild + a quiet-machine A/B
  of >= 8 runs per arm): guest threads at user-interactive QoS, host helper threads at utility QoS.
- The pre-test shader cache of the app fixture is kept in app/work26/cache_aside_20261110/ (the fixture now holds
  the freshly seeded one).

## 2026-11-10 — 0.5.1-f round ("any hitch bothers me", jagged lines still visible)

Result: app/out_perf_f (F16-macOS-0.5.1-f.zip 97 MB, SSD "FIFA 16 v0.5.1-f.app"), renderer build f16 + emulator
rebuilt from shadps4-metal (9 files uncommitted). Earlier bundles untouched. Nothing committed.

- Jagged pitch lines, root cause: NOT missing anti-aliasing. The renderer forces 16x anisotropy on every sampler; the
  pitch shader (ps ed446cb3) reads its line texture through a sampler with a +2 LOD bias as a "line near this pixel"
  mask guarding its own 3x3 supersampling. Anisotropy takes the mip from the minor axis, so at the grazing angle the
  mask no longer reached the pixels beside the line and they skipped the supersampling. Fix: no forced anisotropy on
  samplers with a positive LOD bias (vk_rasterizer.cpp; BB_ANISO_BIASED=1 restores). Verified on snapshots
  (harness/linemetric.py). The 0.5.1-e note "FXAA smooths the pitch lines" was wrong; FXAA stays for other edges.
- Late flips: std::this_thread::yield() is swtch_pri() on macOS (caller depressed to the lowest priority for up to a
  10 ms quantum). bbport::Yield in the renderer and a guest yield in the emulator (SHAD_GUEST_YIELD=legacy restores).
- Game process priority: with the split renderer the emulator has no window, so App Nap clamped every thread to
  utility priority 20 (ps -M). main.cpp KeepProcessInteractive (NSActivityUserInitiated | LatencyCritical;
  SHAD_APP_NAP=1 restores). Guest threads at user-interactive QoS (SHAD_GUEST_QOS=ui|in|off).
- Display cadence. ProMotion in adaptive mode shows frames on 4.17 ms quanta with jitter; a 1x1 pt "heartbeat"
  sublayer recoloured every ~7 ms pins the display to a steady 120 Hz grid (mtl_present.mm StartSteadyRefresh;
  BB_REFRESH_BEAT=0 off; BB_DISPLAY_60=1 switches the display to its 60 Hz mode instead). Paced presents (minimum
  duration 0.97/60 s) keep each frame for two refreshes. Display-path floor: a finished frame needs 21-24 ms from GPU
  end to shown on the 120 Hz grid (28 ms at 60 Hz); a full 3-drawable queue is 48 ms wait, 78-88 ms flip to screen.
- Pacing lock (vk_presenter.cpp PacingLock): slews the present thread's 60 Hz tick (BbPacing::TickSlewNs, at most
  +0.2 / -0.1 ms per frame) so the least wait of the last 8 on-time frames sits at 40 ms: one spare frame hides a
  single late game frame, flip to screen 53 ms instead of 78-88. Target 26 ms (and 12 at 60 Hz) sits on the floor and
  misses on ordinary jitter (r2: 97.6% even). Raising the target on misses was tried and removed (it only chased
  capture artifacts to 45-46 ms = 68 ms latency). Flip completion credit kept (BB_FLIP_CREDIT=0: 95.9% even).
  bbport.ini even_frames (default on; overlay "Even frame times"); off = unpaced, 34 ms, 84% even frames.
- MEASUREMENT ARTIFACT: the "spontaneous lone 25 ms display skips" (0.5-1.4/s, clusters every ~3.3 s) were the
  harness. Every `screencapture` makes the window server skip a refresh (probe pacetest: captures every 2.5 s skip,
  8 threads of CPU load do not). All earlier display-late numbers taken with captures are inflated. Method now:
  QUIET_SECS=45 (fifa_autotest2.sh sleeps without captures once in the match) + harness/quietsum.py.
- Capture-free numbers, in match (even = frames shown 16.7 ms after the previous one):
  heartbeat + paced + lock 40 (default): 100.0% even, 0 late/s, 53 ms flip to screen (r1, q_b; v1 30 s of open play
  with 0 late frames); paced without lock 99.9% at 78 ms; unpaced 83.7% at 34 ms; 60 Hz mode without lock 99.8% at
  87 ms, with lock 99.9% at 54-60 ms.
- What is left and why: (1) GPU-bound cutscenes at 52-56 fps (590+ draws, GPU 16+ ms) show a 16.7/25 ms mix, inherent
  below 60 fps on a fixed grid; (2) game stalls of 40-60 ms about once per 40 s in a match, nearly all in frames that
  register new images (camera cuts, replays): the lock's spare frame turns them into one 25 ms frame; (3) menu and
  pre-kick-off asset loads (stalls over 70 ms: 108 of 118 in run v1 are outside play).
- 07:43 appval_f (packaged app, run app/work26/data_test/runs/20261110_073826): MATCH_OK, 0 critical lines, direct
  page protection, heartbeat on, lock target 40. 07:46 copied to the SSD (ditto; zip cmp identical; all six bundles
  verify; emulator keeps get-task-allow). make_perf_app.sh takes EMU_BIN=<built shadps4> since this round.
- Not done: stadium-edge aliasing, GPU cost of the sampler fix (not measurable in GPU busy), the goal-kick stall A/B
  for the QoS changes (>= 8 runs per arm).

## 2026-11-10 — 0.5.1-g and 0.5.1-h rounds (short record; details in CHANGES-FIFA.md of the two forks)

- 0.5.1-g: texture fixes (dark bodies, blue face, wrong mip level 0: FindImage lost the mip view), flip-based
  pacing lock, opt-in 120 Hz mode in the launcher, start-up patch cache in the emulator (64 s to 16 s).
- 0.5.1-h: one-time draws skipped on a cold pipeline cache (yellow menu players): steady-target rule. FIP balls
  served unmodified.
- Both still carried Resources/shader_seed (and -g/-h Resources/patch_seed): made from the game, so 0.5.1 to
  0.5.1-h are not publishable bundles.

## 2026-11-10 — 0.5.1-i round (nothing game-derived in the app, caches in the savegame folder, publishable)

- Bundle: no shader_seed, no patch_seed. run.sh `place_caches` links `<data>/user/cache` to `<saves>/cache`
  (shader cache `CUSA02138/`, patch record `static_patches/*.spc`), moving an older cache there. The seed
  variables are unset. make_perf_app.sh removes both seed folders, fails on any cache or game file in the bundle,
  replaces the build machine's home folder in the binaries (scrub_build_paths.py, 3386 strings in 17 files) and
  writes an honest SOURCES.txt: "LOCAL BUILD" while a repository has uncommitted changes; RELEASE=1 refuses to
  package unless all four are clean and tagged v<version>.
- First launch: the emulator writes `prepare <0..1000>` to BB_PROGRESS_FILE while it patches the game code
  uncached; the GPU host shows a bar in the game window, the launcher shows "First launch: preparing the game N%".
  While pipelines compile the overlay shows a "Building shaders" note (BB_SHADER_PROGRESS=0 turns it off).
- Root cause of the slow full-screen start: macOS Game Mode. The GPU host is the full-screen game
  (LSApplicationCategoryType games), so Game Mode demoted the emulator process, which runs the game itself, to the
  background role (all threads at priority 4) from about 2 s after its start until it first played sound.
  A process with a running audio output is exempt: the emulator now keeps a silent AudioToolbox output queue
  (main.cpp KeepAudioActive, SHAD_BOOT_AUDIO=0 turns it off). Full screen, new user: first picture 57-60 s -> 14 s,
  code preparation 46-55 s -> 7.2 s; second start 16 s -> 7 s. Game Mode stays on for the host.
  Checked and rejected: LSSupportsGameMode=NO on the host (works, but loses Game Mode), SDL background app flag
  (still demoted), App Nap opt-out (no effect).
- Launcher: "Cache: <size>" and "Clear Cache…" beside the savegame folder (CacheStore), the preparing row, a stale
  refresh no longer reports "The game exited." for a running game, the "Other emulator running" note is hidden
  while starting. 128 checks pass. SwiftUI @State does not compile with this command-line toolchain (macro plugin
  missing): view flags are @Published on the model.
- Validation of the final bundle (app/out_perf_i): packaged-app match check MATCH_OK twice (59.5 and 59.9 fps,
  p99 23.5 and 21.8 ms, GPU 9.1 and 9.7 ms; before the change 59.9 / 22.7 / 9.2), every binary's signature valid,
  emulator keeps get-task-allow.
- Audit for publication: see the 0.5.1-i hand-over. Not committed, not tagged, not pushed.

## 2026-11-10 — v0.5.1 release (the 0.5.1-i round, tagged)

- The last development round, 0.5.1-i, is the release v0.5.1. The interim bundles 0.5.1 to 0.5.1-i are deleted:
  0.5.1 to 0.5.1-h carried the translated shader cache and must never be published.
- Found while preparing the release: the 0.5.1-i bundle carried an x86 libbbgpu (the game-side library) built
  before the last source changes, because only the arm64 side had been rebuilt. Rebuilt (41 objects), and
  `RELEASE=1` now refuses to package while a build directory is not up to date (make_perf_app.sh).
- The release is packaged from the v0.5.0 bundle (app/out_host26) as base:
  `RELEASE=1 EMU_BIN=<shadps4> LAUNCHER_BIN=<F16> make_perf_app.sh 0.5.1` -> app/out_perf. It differs from the
  0.5.1-i bundle only in the x86 libbbgpu, Info.plist, SOURCES.txt and the signatures.
- Validation of the release candidate (same binaries, before the commits): packaged-app match check MATCH_OK,
  17 windows, 59.9 fps, p99 21.5 ms, max 36.7 ms, 0 hitches, GPU 11.1 ms; first launch in full screen with no
  cache: preparation 8 s, first picture 14 s, caches created in <savegame folder>/cache.
- Publication hygiene: local tags and one branch whose commits carried a personal email or the machine name
  were removed from the renderer, emulator and mods repositories (none was ever pushed). Four old scripts in
  home/ take their scratch folder from FIFA_SCRATCH.
- To publish: push each branch and the tag v0.5.1 by name to the fork remotes, then upload F16-macOS-0.5.1.zip.

## 2026-11-10 — v0.5.1 licence audit before publishing (release re-cut)

Audit of the bundle and the four repositories before the first push of v0.5.1. Three things were wrong and are fixed:

- The emulator linked Fraunhofer FDK AAC and LibreSSL statically. The FDK AAC licence and the OpenSSL/SSLeay
  licences are not GPL-compatible, so a redistributed GPL binary must not contain them. The fork has a new CMake
  option `ENABLE_GPL_INCOMPATIBLE_LIBS` (default OFF): an AAC decoder instance is refused (FIFA 16 never creates
  one), libSceHttp HTTPS uses upstream's mock path, the P2P packet crypto uses CommonCrypto (checked against
  `openssl enc -aes-128-cfb` and HMAC-SHA1 reference output). `make_perf_app.sh` refuses an emulator that still
  has `aacDecoder_Open`, `SSL_CTX_new` or `EVP_CipherInit_ex`.
- The edge anti-aliasing shader is a port of NVIDIA FXAA 3.11 (BSD-3-Clause), not public domain as a comment said:
  the notice is in the renderer at `gpu/third_party/fxaa/LICENSE.txt` and in the bundle.
- The notices of the libraries statically linked into the emulator and the renderer were not in the bundle.
  `app/make_third_party_licenses.py <emulator checkout> <renderer checkout>` writes
  `app/licenses/THIRD-PARTY-LICENSES.txt` (48 libraries); the packaging now takes NOTICE and Licenses from
  `app/` instead of inheriting the v0.5.0 texts.

Validation of the re-cut candidate (packaged app, full-screen match): MATCH_OK, 17 windows, 60.0 fps, mean p99
19.6 ms, max 34.2 ms, 0 hitches. The tag v0.5.1 was moved to the new commits before anything was pushed.
The published v0.5.0 asset still has the old linkage and the shorter notices.
