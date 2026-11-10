#!/bin/bash
# priohelper.sh <label> : once the run reports the match, lists nice values up the launch chain and
# thread priorities of the emulator and the GPU host.
S=${S:-${TMPDIR:-/tmp}/fifa_harness}; mkdir -p "$S"   # scratch folder for logs and intermediate files
R=$S/results/$1.txt
for i in $(seq 1 240); do grep -q "match running at" "$R" 2>/dev/null && break; grep -q "=== done" "$R" 2>/dev/null && exit 0; sleep 5; done
sleep 20
{
  p=$(pgrep -x shadps4 | head -1); echo "== launch chain (pid ppid nice pri command)"
  while [ -n "$p" ] && [ "$p" -gt 1 ]; do ps -o pid=,ppid=,nice=,pri=,comm= -p $p | cut -c1-90; p=$(ps -o ppid= -p $p | tr -d ' '); done
  for n in shadps4 bbgpu-host bbgpu-host-macos27 bbgpu-host-macos26; do
    for p in $(pgrep -x $n); do echo "== $n $p"; ps -M -p $p | cut -c1-110; done
  done
} > $S/prio_$1.txt 2>&1
