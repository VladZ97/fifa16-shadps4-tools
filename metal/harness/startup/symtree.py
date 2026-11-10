import sys, re, bisect, subprocess
syms = []
for l in open(sys.argv[1]):
    p = l.split(None, 2)
    if len(p) == 3: syms.append((int(p[0], 16), p[2].strip()))
syms.sort(); keys = [s[0] for s in syms]
def name(a):
    i = bisect.bisect_right(keys, a) - 1
    return syms[i][1] if i >= 0 else hex(a)
depth_target = int(sys.argv[3]); maxdepth = int(sys.argv[4])
out = []
for l in open(sys.argv[2], encoding='latin1'):
    m = re.match(r'^(\s+[+!:| ]*?)(\d+) \?\?\?  \(in shadps4\)  load address \S+ \+ (0x[0-9a-f]+)', l)
    if not m: continue
    d = len(m.group(1)); n = int(m.group(2))
    if depth_target <= d <= maxdepth and n >= int(sys.argv[5]):
        out.append((d, n, name(0x700000000000 + int(m.group(3), 16))))
names = sorted(set(o[2] for o in out))
dem = dict(zip(names, subprocess.run(['c++filt'], input='\n'.join(names), capture_output=True, text=True).stdout.split('\n')))
for d, n, s in out:
    print(' ' * (d - depth_target), n, re.sub(r'\(.*', '', dem[s])[:90])
