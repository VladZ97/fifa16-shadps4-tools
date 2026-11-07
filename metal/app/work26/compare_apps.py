#!/usr/bin/env python3
"""Compares two .app bundles file by file. Mach-O files are compared after removing their code
signature from temporary copies (codesign --remove-signature), so a re-sign is not a change."""
import hashlib, os, shutil, struct, subprocess, sys, tempfile
MAGICS = {0xfeedfacf, 0xcffaedfe, 0xcafebabe, 0xbebafeca}
def digest(path, tmp):
    with open(path, 'rb') as f: head = f.read(4)
    if len(head) == 4 and struct.unpack('<I', head)[0] in MAGICS:
        t = os.path.join(tmp, 'x'); shutil.copyfile(path, t)
        subprocess.run(['codesign', '--remove-signature', t], capture_output=True)
        path = t
    return hashlib.sha256(open(path, 'rb').read()).hexdigest()
def walk(root):
    out = {}
    for d, _, files in os.walk(root):
        for f in files:
            p = os.path.join(d, f); out[os.path.relpath(p, root)] = p
    return out
a, b = walk(sys.argv[1]), walk(sys.argv[2]); changed = []
with tempfile.TemporaryDirectory() as tmp:
    for rel in sorted(set(a) | set(b)):
        if '_CodeSignature' in rel or rel.endswith('.DS_Store') or os.path.basename(rel).startswith('._'): continue
        if rel not in a or rel not in b: changed.append((rel, 'only in ' + ('first' if rel in a else 'second'))); continue
        if digest(a[rel], tmp) != digest(b[rel], tmp): changed.append((rel, 'differs'))
print(f"{len(a)} / {len(b)} files; {len(changed)} differ (code signatures ignored)")
for rel, why in changed: print(f"  {why}: {rel}")
