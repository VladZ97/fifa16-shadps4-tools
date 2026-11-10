#!/usr/bin/env python3
"""quietsum.py <run dir> ...: frame cadence inside the capture-free stretch of a run (report.txt QUIET start/end,
emulator.log PTT/PT trace lines from BB_PACING_TRACE=1), and in the 20 s of the match around it for contrast."""
import sys, re, collections
def stats(fr, name):
    if not fr: print(f'  {name}: no frames'); return
    iv=[f[0] for f in fr]; n=len(iv)
    h=collections.Counter(round(x/4.1667)*4.1667 for x in iv)
    even=sum(1 for x in iv if 14.6<x<18.8)
    late=[f for f in fr if f[0]>21.7]; lone=[f for f in late if 0<f[2]<21.7]
    short=sum(1 for x in iv if 0<x<12.6)
    w=[f[1] for f in fr if f[1]>0]
    secs=sum(iv)/1000
    hs=' '.join(f'{k:.1f}:{v}' for k,v in sorted(h.items()) if abs(k-16.67)>1)
    print(f'  {name}: {secs:5.1f} s, {n} frames, {n/secs:5.2f} shown per s | even {100.0*even/n:5.1f}% | late {len(late)} ({len(late)/secs:.2f}/s; ready on time {len(lone)}) short {short} | '
          f'wait mean {sum(w)/max(len(w),1):4.1f} least {min(w) if w else 0:4.1f} | worst {max(iv):.0f} ms | other intervals {hs or "none"}')
def main(run):
    run=run.rstrip('/'); q0=q1=None
    for l in open(run+'/report.txt',errors='replace'):
        m=re.match(r'QUIET (start|end) (\d+)',l)
        if m:
            if m.group(1)=='start': q0=int(m.group(2))
            else: q1=int(m.group(2))
    frames=[]; t=None; lats=[]; locks=[]
    for raw in open(run+'/emulator.log','rb'):
        l=raw.decode('latin-1')
        if l.startswith('PTT:'): t=float(l.split()[1])
        elif l.startswith('Latency') and t is not None:
            m=re.search(r'frames\): ([\d.]+) ms',l)
            if m: lats.append((t,float(m.group(1))))
        elif l.startswith('Pacing lock') and t is not None:
            m=re.search(r'target ([\d.]+) ms',l)
            if m: locks.append((t,float(m.group(1))))
        elif l.startswith('PT:') and t is not None:
            fr=[]
            for tok in l.split()[1:]:
                try: fr.append(tuple(float(x) for x in tok.split('/')))
                except ValueError: break  # another thread's log line cut into this one
            tt=t
            for f in reversed(fr):
                frames.append((tt,f)); tt-=f[0]/1000
    frames.sort(key=lambda x:x[0])
    print('==',run.split('/')[-1],'quiet window',None if q0 is None else q1-q0,'s')
    if q0 is None or q1 is None: return
    stats([f for t,f in frames if q0+2<=t<=q1-1],'quiet  ')
    ql=[v for t,v in lats if q0+7<=t<=q1+1]; qt=[v for t,v in locks if q0+2<=t<=q1]
    print(f"           flip to screen in the quiet stretch {sum(ql)/max(len(ql),1):.1f} ms over {len(ql)} windows; lock target {min(qt) if qt else 0:.0f}-{max(qt) if qt else 0:.0f} ms")
    if ql:
        sq=sorted(ql); print(f"           flip to screen windows: least {sq[0]:.1f} median {sq[len(sq)//2]:.1f} most {sq[-1]:.1f} ms")
    fw=[f[4] for t,f in frames if q0+2<=t<=q1-1 and len(f)>4 and f[4]>0]
    if fw:
        fw.sort(); print(f"           host flip to shown per frame: p5 {fw[len(fw)//20]:.1f} median {fw[len(fw)//2]:.1f} p95 {fw[len(fw)*19//20]:.1f} most {fw[-1]:.1f} ms")
    stats([f for t,f in frames if q0-8<=t<q0 or q1<t<=q1+12],'capture')
for r in sys.argv[1:]: main(r)
