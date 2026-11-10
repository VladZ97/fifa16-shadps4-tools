# Measured-run queue (2026-11-09)

Scripts that drive `~/fifa_autotest2.sh drive metal` runs one after another with guards against stuck sessions.
`BB_QUEUE_DIR` (default `~/fifa_metal/queue`) holds `results/<label>.txt`, `guard.log` and the `build.lock` file.

- `runq4.sh <label> [VAR=value ...]` – one match run with extra environment; waits for a running test and for
  `build.lock` (touch it around any libbbgpu/host rebuild: the host loads the dylib straight from the build output);
  kills the run after `RUN_MAX` (1100 s); summarises report, Frame stats, Protects, [SPIN], [STALL] lines.
- `qguard4.sh` – watchdog loop: kills a test older than RUN_MAX, an emulator/host without a driver for 120 s, a run whose
  results file is idle for 1000 s (long matches write their report late), and a sampler waiting for a run that never comes.
- `cutsample3.sh <label>` – samples the GPU host (1 ms, 4 s, up to 3 times) while the run shows >= 700 draws/frame.
- `cpsample.py <sample> [thread]`, `cpcallers.py <sample> <leaf regex>` – self/inclusive and caller analysis of a sample.

Chain runs on a pid (`kill -0`) or the lock file, never `pgrep -f <script name>` (a background task's shell wrapper
carries the whole script text, so every waiter matches every other).

## 0.5.1-g additions (2026-11-10)

- `pcrun.sh <label> [VAR=value ...]`: one measured match run with a startup timeline (written for the session scratchpad:
  set `S` at its top to a results folder first).
- `fsum.py <emulator logs...>`: match-phase averages of the "Frame stats" lines (fps, worst frame, us/draw, GPU busy).
- `quietsum.py <run dir>`: now also prints flip-to-screen windows and the per-frame "host flip to shown" percentiles
  (5th trace field of BB_PACING_TRACE=1). Its "even %" assumes a 60 Hz cadence: read the interval list at 120 Hz.
- `texture_trace/`: readers for the BB_BCSEQ=1 [SEQ] trace and texture dumps (disc.py, lv0gpu.py, mips.py, exact.py,
  sig.py, sheet0.py, bc1.py and helpers) used for the dark-body, blue-face and wrong-mip-level bugs.
- `startup/`: bootwatch3.sh and sample_start.sh (timeline and `sample` of a start), threadtop.py and symtree.py
  (per-thread call trees from a sample; the emulator needs `nm -n` symbols, `atos` does not resolve it).
- `home/fifa_autotest2.sh`: the frozen-picture timer is reset after a QUIET_SECS stretch.
