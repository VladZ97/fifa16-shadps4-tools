---
name: feedback-judge-runs-early
description: "User feedback - detect bad/stuck test runs automatically and abort fast; drive mode has STALL / VISUAL_BAD verdicts vs perf-build reference shots"
metadata:
  type: feedback
---

Test drives must catch broken visuals and hangs by themselves and abort right away, instead of me narrating state transitions or the user spotting it.

**Why:** 2026-10-29 the user had to point out twice that a Metal run was bad (black triangle / bad kits at kit select, then stuck on stadium entry): "Be quicker on decision", "Improve on detecting those yourself".
**How to apply:** `fifa_autotest.sh drive metal` (sandbox disabled; `run` is the old replay mode) now prints `VERDICT: MATCH_OK|VISUAL_BAD|STALL|EXITED|ENDED_IN_<state>`. It compares each stable screen against ~/fifa_perf/autotest/refs/<state>.jpg (recorded from the good perf build with `REF_SAVE=1 ... drive perf`) using ~/fifa_perf/autotest/imgcheck.py (mean cell diff > 25, match > 45, or dark fraction +0.10). It aborts on a picture frozen for 60 s and keeps $DIR/BAD_*.jpg. Always read the BAD_ shot and the VERDICT line; KEEP_SHOTS is a count (KEEP_SHOTS=1 keeps only one shot). Related: [[feedback-verify-before-measuring]], [[fifa16-metal-hybrid-project]].
