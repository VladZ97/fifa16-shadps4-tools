#!/usr/bin/env python3
"""Which files did the game request through the patch overlay that exist nowhere?

  fip_missing.py --log <shadPS4 log> --game <game folder> [--update <game-UPDATE folder>] --patch <patch folder>

Reads every `open: path = /download0/...` line from the log, subtracts files present in the
patch folder and entries inside the game's .big archives (base + update), ignores the
engine's optional `specific*` probes, and prints the rest grouped by folder, plus the list of
players whose main head file is missing (the headless ones).
"""
import argparse, os, re, sys, collections
sys.path.insert(0, os.path.dirname(__file__)); from big4 import entries

def main():
    p = argparse.ArgumentParser(); p.add_argument("--log", required=True); p.add_argument("--game", required=True)
    p.add_argument("--update"); p.add_argument("--patch", required=True); a = p.parse_args()
    have = set()
    for root in filter(None, [a.game, a.update]):
        for big in os.listdir(root):
            if big.endswith(".big"):
                try: have |= {n.lower().replace("\\", "/") for n, o, s in entries(os.path.join(root, big))}
                except Exception: pass
    for r, d, fs in os.walk(a.patch):
        for f in fs:
            if not f.startswith("._"): have.add(os.path.relpath(os.path.join(r, f), a.patch).lower().replace("\\", "/"))
    req = set()
    for line in open(a.log, errors="replace"):
        m = re.search(r"open: path = /download0/([^ ]+)", line)
        if m: req.add(m.group(1).lower())
    missing = sorted(x for x in req if x not in have and "specific" not in x)
    print(f"requested through overlay: {len(req)}   missing everywhere: {len(missing)}")
    for k, v in collections.Counter("/".join(x.split("/")[:3]) for x in missing).most_common(): print(f"{v:6d} {k}")
    heads = sorted({re.search(r"head_(\d+)_", x).group(1) for x in missing if re.search(r"/heads/head_\d+_0\.rx3$", x)})
    print(f"\nplayers with no main head file anywhere ({len(heads)}): {' '.join(heads)}")
    crowd = [x for x in missing if "/crowd/crowdkit_" in x]
    if crowd: print(f"\ncrowdkit files requested but absent: {len(crowd)} -> apply the crowd.lua fallback (references/lua-fixes.md)")

if __name__ == "__main__": main()
