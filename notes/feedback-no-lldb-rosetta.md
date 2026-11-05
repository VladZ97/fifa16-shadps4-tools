---
name: feedback-no-lldb-rosetta
description: Never run lldb/debugserver on the x86 shadps4 under Rosetta — it wedged oahd and every new x86 binary hung at exec
metadata:
  type: feedback
---
Don't launch shadps4 (x86, Rosetta) under lldb. On 2026-10-30 an `lldb --batch -o run` hung, left a debugserver, and Rosetta's oahd then blocked every not-yet-translated x86 binary at exec (U state, unkillable; `sample` hung too). `sudo launchctl kickstart -k system/com.apple.oahd` is refused by SIP; it cleared by itself after ~10 minutes.

**Why:** the user had to step in, and all testing stalled.

**How to apply:** for crashes use SHAD_FAULT_DIAG=1 (synchronous backtrace to stderr in core/signals.cpp) or fprintf tracing; check `timeout 15 /tmp/zsmall` (tiny x86 binary) if launches hang. See [[fifa16-metal-hybrid-project]].
