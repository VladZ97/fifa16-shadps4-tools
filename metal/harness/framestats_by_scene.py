import re,sys
for r in sys.argv[1:]:
    rows=[]
    for l in open(r+'/emulator.log','rb'):
        l=l.decode('latin1')
        m=re.search(r'Frame stats: ([0-9.]+) FPS, worst frame ([0-9.]+) ms.*?([0-9.]+) us/draw, (\d+) draws/frame, idle ([0-9.]+)%.*GPU busy ([0-9.]+) ms', l)
        if m: rows.append(tuple(float(x) for x in m.groups()))
    def agg(sel,name):
        s=[x for x in rows if sel(x)]
        if not s: print(name,'none'); return
        f=sorted(x[0] for x in s)
        print(f"{name}: n={len(s)} fps mean {sum(f)/len(f):.1f} min {f[0]:.1f} p10 {f[len(f)//10]:.1f} | worst-frame mean {sum(x[1] for x in s)/len(s):.1f} | gpu busy {sum(x[5] for x in s)/len(s):.2f} | us/draw {sum(x[2] for x in s)/len(s):.2f} idle {sum(x[4] for x in s)/len(s):.1f}")
    print('==',r)
    agg(lambda x: x[3]>=650 and x[0]>30,'cutscene >=650 draws')
    agg(lambda x: 250<=x[3]<650 and x[0]>30,'match 250-650 draws')
    for x in rows:
        if x[3]>=650 and x[0]>30: print('   ',x)
