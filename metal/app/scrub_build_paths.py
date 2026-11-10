#!/usr/bin/env python3
# scrub_build_paths.py <F16.app>: replaces the build machine's home folder in every bundle file with a neutral
# path of the same length, so a published bundle does not carry the builder's account name.
#
# The compilers record source paths in three places: assert/log messages (__FILE__), the debug symbol table
# (source and object file names) and FFmpeg's "configuration:" string. None of them is read at run time, and a
# same-length replacement moves no byte of the file, so only the code signature changes (the packaging script
# signs after this step). Files with an absolute load path under the home folder are refused: those would be
# broken on any other Mac and must be fixed where they are built.
#
# Run by make_perf_app.sh. Exit status 1 if a home path remains afterwards.
import os, subprocess, sys

def main():
    app = sys.argv[1]
    home = os.path.expanduser("~").rstrip("/")
    name = os.path.basename(home)
    old = (os.path.dirname(home) + "/" + name + "/").encode()
    neutral = ("buildserver" * (len(name) // 11 + 1))[:len(name)]
    new = (os.path.dirname(home) + "/" + neutral + "/").encode()
    assert len(old) == len(new)
    changed = 0; count = 0
    for folder, _, files in os.walk(app):
        for f in files:
            p = os.path.join(folder, f)
            if os.path.islink(p):
                continue
            data = open(p, "rb").read()
            n = data.count(old)
            if not n:
                continue
            macho = data[:4] in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xce\xfa\xed\xfe")
            if macho:
                load = subprocess.run(["otool", "-l", p], capture_output=True, text=True).stdout
                bad = [l.strip() for l in load.splitlines()
                       if (" name " in l or " path " in l) and home in l]
                if bad:
                    print(f"absolute load path under the home folder in {p}: {bad[0]}"); return 1
            mode = os.stat(p).st_mode
            with open(p, "wb") as out:
                out.write(data.replace(old, new))
            os.chmod(p, mode)
            if macho:
                # The old signature no longer matches the file; an ad-hoc one is put back here because the
                # bundle signature made later does not re-sign libraries under Resources.
                r = subprocess.run(["codesign", "--force", "--sign", "-", p], capture_output=True, text=True)
                if r.returncode != 0:
                    print(f"cannot re-sign {p}: {r.stderr.strip()}"); return 1
            changed += 1; count += n
    left = []
    needle = name.encode()
    for folder, _, files in os.walk(app):
        for f in files:
            p = os.path.join(folder, f)
            if not os.path.islink(p) and needle in open(p, "rb").read():
                left.append(os.path.relpath(p, app))
    if left:
        print("build-machine account name still in:", ", ".join(left[:5])); return 1
    print(f"build paths: {count} replaced in {changed} files, none left")
    return 0

sys.exit(main())
