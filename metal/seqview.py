#!/usr/bin/env python3
# seqview.py <run dir>: compact view of the [SEQ] ordered log (shadow maps, clears, waits, fences).
import sys,re,collections
R=sys.argv[1]; lines=[l.rstrip() for l in open(R+'/seq.txt')]
print(len(lines),"events")
kinds=collections.Counter(l.split()[2] for l in lines if len(l.split())>2); print(kinds.most_common(20))
# frame windows: start at each draw-rt of the first map seen
first=None; shown=0
for i,l in enumerate(lines):
    if 'draw-rt' in l and first is None: first=i
if first is None: sys.exit()
n=int(sys.argv[2]) if len(sys.argv)>2 else 3
out=[]; frames=0
for l in lines[first:]:
    if 'draw-rt' in l and ('0x461ea0000' in l):
        frames+=1
        if frames>n: break
        out.append("---- frame ----")
    if 'dispatch ' in l and '3ba88f63' not in l: continue
    out.append(l.replace('[SEQ] ',''))
print('\n'.join(out))
