# shadPS4 notes relevant to patching

## Overlay folders

- `/app0` is the game folder with overlays, highest first: `<TITLEID>-mods`,
  `<TITLEID>-UPDATE`, `<TITLEID>-patch`, base. Root ini overrides (`cl.ini`) go in `-mods`.
- `/download0` is `~/Library/Application Support/shadPS4/download/<TITLEID>/`; a symlink to
  an external drive works. This is where almost all loose data lookups go.
- The log (`~/Library/Application Support/shadPS4/log/shad_log.txt`, or the file your runner
  writes) records every probe: `open: path = /download0/...` and
  `Opening path ... failed, file does not exist`. Probes that fail in both `/download0` and
  `/app0` but exist inside a `.big` are not errors; `scripts/fip_missing.py` subtracts the
  archive contents.

## Settings that mattered for FIFA 16 on Apple Silicon (keep when patching)

- `Audio.sdl_mic_device = "None"`: with a real mic the render thread blocked in
  `sceAudioInGetSilentState` every frame (2 FPS).
- `GPU.readbacks_mode = 2` (Precise) and `GPU.readback_linear_images_enabled = true`: the
  game decodes textures with compute shaders and the CPU re-reads them; without readbacks
  every streamed texture is noise. Relaxed mode brings the kit-screen noise back.
- `GPU.direct_memory_access_enabled = true`: needed for the kit-selection textures.

## Claude Code sandbox gotchas on macOS

- The shell can read the game folder but may get "Operation not permitted" on other paths of
  an external drive and on `~/Downloads`; use `dangerouslyDisableSandbox` for reads, and use
  Spotlight (`mdfind -onlyin ~/Downloads ...`) to see downloads you cannot list. Ask the user
  to move archives to the external drive.
- The auto-mode classifier refuses to compile or run downloaded third-party code; hand such
  commands to the user as a script.
