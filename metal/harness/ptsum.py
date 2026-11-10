import sys
# usage: ptsum.py <run dir> [first chunk] [last chunk]
r=sys.argv[1]; a=int(sys.argv[2]) if len(sys.argv)>2 else 0; b=int(sys.argv[3]) if len(sys.argv)>3 else 10**9
chunks=[]; draws=[]
cur_draws=0
for l in open(r+'/emulator.log','rb'):
    l=l.decode('latin1')
    if l.startswith('PT:'):
        fr=[tuple(float(x) for x in t.split('/')) for t in l.split()[1:]]
        chunks.append(fr)
print('chunks',len(chunks))
for ci,fr in enumerate(chunks):
    if ci<a or ci>b or not fr: continue
    w=[f[1] for f in fr if f[1]>0]
    late=[i for i,f in enumerate(fr) if f[0]>21.7]
    short=[i for i,f in enumerate(fr) if 0<f[0]<12.6]
    ev=[]
    for i in late:
        prev=fr[i-1][1] if i>0 else -1
        nxt=fr[i+1][0] if i+1<len(fr) else -1
        ev.append(f"[{fr[i][0]:.0f} ready {fr[i][2]:.0f} prevwait {prev:.0f} wait {fr[i][1]:.0f} next {nxt:.0f}]")
    slew=sum(f[3] for f in fr)
    rd=sorted(f[2] for f in fr if f[2]>0)
    print(f"{ci:3d} n {len(fr):3d} wait least {min(w) if w else 0:4.1f} mean {sum(w)/max(len(w),1):4.1f} | ready p5 {rd[len(rd)//20] if rd else 0:4.1f} p95 {rd[len(rd)*19//20] if rd else 0:4.1f} max {rd[-1] if rd else 0:5.1f} | late {len(late)} short {len(short)} slew {slew:+5.1f} {' '.join(ev[:4])}")
