import sys,collections
# usage: ptpos.py <run dir> [first chunk] [last chunk]: where in the 2 s chunk lone late frames fall, gaps between them
r=sys.argv[1]; a=int(sys.argv[2]) if len(sys.argv)>2 else 0; b=int(sys.argv[3]) if len(sys.argv)>3 else 10**9
chunks=[]
for l in open(r+'/emulator.log','rb'):
    l=l.decode('latin1')
    if l.startswith('PT:'):
        chunks.append([tuple(float(x) for x in t.split('/')) for t in l.split()[1:]])
t=0.0; lates=[]; pos=collections.Counter(); n=0
for ci,fr in enumerate(chunks):
    for i,f in enumerate(fr):
        t+=f[0]
        if a<=ci<=b:
            n+=1
            if f[0]>21.7 and f[2]<21.7:
                lates.append(t); pos[i*10//max(len(fr),1)]+=1
gaps=[round((y-x)/1000,2) for x,y in zip(lates,lates[1:])]
print('frames',n,'spontaneous late',len(lates),'per s %.2f'%(len(lates)/(n/60.0) if n else 0))
print('position decile in chunk',[pos[i] for i in range(10)])
print('gaps s',gaps[:60])
