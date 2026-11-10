#!/bin/bash
# sample_start.sh <label> <seconds>: samples the emulator from its first second.
S=${S:-${TMPDIR:-/tmp}/fifa_harness}; mkdir -p "$S"   # scratch folder for logs and intermediate files
until [ -f $S/boot/$1.ts ]; do sleep 1; done
until P=$(pgrep -x shadps4 | head -1) && [ -n "$P" ]; do sleep 0.2; done
sample $P ${2:-14} 1 -file $S/boot/$1.sample > /dev/null 2>&1
echo "sampled $P $(date +%H:%M:%S)"
