---
name: feedback-verify-before-measuring
description: User feedback - verify an automated measurement really captures the intended scene/state (look at the screenshot) before running a whole batch; wrong-scene benchmarks wasted time
metadata:
  type: feedback
---

Before trusting or batching any automated measurement (FPS/GPU benchmark, state-driven test), confirm from the actual screenshot/OCR text that the driver is on the intended screen and that the readings are being captured (non-empty), on the first run, before launching the remaining runs.

**Why:** On 2026-10-28 a 4-run GPU benchmark dwelled on the team-confirmation screen instead of the kit screen (state label mix-up) and the baseline run captured no overlay readings; the user: "Double check always that you check what you mean, don't waste time."
**How to apply:** For batch runs: run one, inspect the screenshot and the parsed numbers, then continue. Name states by what is on screen, not by what was expected. Related: [[fifa16-shadps4-mac-setup]].
