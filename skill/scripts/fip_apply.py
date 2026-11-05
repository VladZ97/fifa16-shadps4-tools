#!/usr/bin/env python3
"""Replicate the FIP Patch Manager's install steps on macOS.

  fip_apply.py updates  <patch folder> <archive>...     extract update archives in the given order
  fip_apply.py version  <patch folder> "<variant>"      apply fip/version/<variant> + versionassets
  fip_apply.py theme    <patch folder> "<theme name>"   apply fip/theme/<name>
  fip_apply.py facepack <patch folder> <archive>...     extract face packs (top folder stripped)
  fip_apply.py list     <patch folder>                  show variants, themes, applied.ini

Update and face-pack archives contain a single top-level folder ("Manual Install",
"Manual Install Facepack"); it is stripped so files land in the patch root. Every file
overwritten by version/theme application is kept under fip/_overwritten_by_mac_apply/.
Requires `unrar` (brew install rar) or `7zz` for .7z/.zip.
"""
import os, sys, subprocess, shutil, datetime

def run(cmd):
    print("+", " ".join(cmd)); r = subprocess.run(cmd, capture_output=True, text=True)
    tail = (r.stdout + r.stderr).strip().splitlines()[-3:]
    print("\n".join("  " + l for l in tail)); return r.returncode

def top_folder(archive):
    out = subprocess.run(["unrar", "lb", archive], capture_output=True, text=True).stdout.split("\n")
    first = next((l for l in out if l.strip()), "")
    return first.split("/")[0] if "/" in first else ""

def extract(archive, dest):
    if archive.lower().endswith(".rar"):
        top = top_folder(archive)
        cmd = ["unrar", "x", "-o+", "-y", "-idq"] + ([f"-ap{top}"] if top else []) + [archive, dest + "/"]
    else:
        cmd = ["7zz", "x", "-y", f"-o{dest}", archive]
    return run(cmd)

def copy_tree(src, dst, backup, skip=()):
    n = 0
    for root, _, files in os.walk(src):
        for f in files:
            if f.startswith("._") or f in skip: continue
            rel = os.path.relpath(os.path.join(root, f), src); target = os.path.join(dst, rel)
            if os.path.exists(target):
                b = os.path.join(backup, rel); os.makedirs(os.path.dirname(b), exist_ok=True)
                if not os.path.exists(b): shutil.copy2(target, b)
            os.makedirs(os.path.dirname(target), exist_ok=True); shutil.copy2(os.path.join(root, f), target); n += 1
    return n

NATION_ASSETS = [("data/ui/imgAssets/flags512x512/f_{}.dds"), ("data/ui/artassets/cardflags/{}.big"),
                 ("data/ui/artassets/countryflags/f_{}.big"), ("data/ui/artassets/miniflags/flag_{}.big")]
LEAGUE_ASSETS = ["data/ui/imgAssets/league/dark/l{}.dds", "data/ui/imgAssets/league/light/l{}.dds",
                 "data/ui/imgAssets/league512x128/dark/l{}.dds", "data/ui/imgAssets/league512x128/light/l{}.dds",
                 "data/ui/imgAssets/leaguelogos_tiny/dark/l{}.dds", "data/ui/imgAssets/leaguelogos_tiny/light/l{}.dds",
                 "data/ui/imgAssets/league/l{}.dds", "data/ui/imgAssets/leaguelogos_sm/dark/l{}.dds",
                 "data/ui/imgAssets/leaguelogos_sm/l{}.dds", "data/ui/imgAssets/leaguelogos_tiny/l{}.dds",
                 "data/ui/imgAssets/trophy/t{}.dds", "data/ui/imgAssets/trophy256x256/t{}.dds", "data/ui/imgAssets/trophy128x128/t{}.dds"]

def apply_id_swaps(patch, variant_dir, backup):
    """Variants reuse nation/league ids (e.g. Israel takes Peru's slot). The manager copies each
    pair's flag/logo artwork from fip/versionassets onto the other's id, in both directions."""
    va = os.path.join(patch, "fip", "versionassets")
    for ini, assets, label in (("nationidswaps.ini", NATION_ASSETS, "nation"), ("leagueidswaps.ini", LEAGUE_ASSETS, "league")):
        f = os.path.join(variant_dir, "fip", "version", ini)
        if not os.path.exists(f): continue
        n = 0
        for line in open(f, errors="replace"):
            parts = [x.strip() for x in line.strip().split(",")]
            if len(parts) != 2 or not all(parts): continue
            for a, b in ((parts[0], parts[1]), (parts[1], parts[0])):
                for tpl in assets:
                    srcf = os.path.join(va, tpl.format(a)); dstf = os.path.join(patch, tpl.format(b))
                    if os.path.exists(srcf):
                        if os.path.exists(dstf):
                            bk = os.path.join(backup, tpl.format(b)); os.makedirs(os.path.dirname(bk), exist_ok=True)
                            if not os.path.exists(bk): shutil.copy2(dstf, bk)
                        os.makedirs(os.path.dirname(dstf), exist_ok=True); shutil.copy2(srcf, dstf); n += 1
        print(f"{label} id swaps: {n} files")

def main():
    if len(sys.argv) < 3: print(__doc__); sys.exit(1)
    cmd, patch = sys.argv[1], os.path.abspath(sys.argv[2]); args = sys.argv[3:]
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M"); backup = os.path.join(patch, "fip", "_overwritten_by_mac_apply", stamp)
    if cmd == "list":
        vd = os.path.join(patch, "fip", "version"); td = os.path.join(patch, "fip", "theme")
        print("applied:", open(os.path.join(vd, "applied.ini")).read().strip() if os.path.exists(os.path.join(vd, "applied.ini")) else "(none)")
        print("variants:", [d for d in sorted(os.listdir(vd)) if os.path.isdir(os.path.join(vd, d))] if os.path.isdir(vd) else [])
        print("themes:", [d for d in sorted(os.listdir(td)) if os.path.isdir(os.path.join(td, d))] if os.path.isdir(td) else [])
    elif cmd in ("updates", "facepack"):
        for a in args: print("###", os.path.basename(a)); extract(os.path.abspath(a), patch)
    elif cmd == "version":
        v = args[0]; src = os.path.join(patch, "fip", "version", v)
        if not os.path.isdir(src): sys.exit(f"no such variant: {v}")
        n = copy_tree(src, patch, backup, skip=("notes.txt",)); print(f"version {v}: {n} files")
        va = os.path.join(patch, "fip", "versionassets")
        if os.path.isdir(va): print("versionassets:", copy_tree(va, patch, backup), "files")
        apply_id_swaps(patch, src, backup)
        open(os.path.join(patch, "fip", "version", "applied.ini"), "w").write(v)
    elif cmd == "theme":
        t = args[0]; src = os.path.join(patch, "fip", "theme", t)
        if not os.path.isdir(src): sys.exit(f"no such theme: {t}")
        print(f"theme {t}:", copy_tree(src, patch, backup, skip=("preview.png",)), "files")
    else: print(__doc__); sys.exit(1)

if __name__ == "__main__": main()
