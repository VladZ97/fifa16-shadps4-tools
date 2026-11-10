# exact.py <dir>: per dumped GPU-compressed image, is GPU level 0 the same set of 8-byte blocks as guest level 0?
import sys,os,re,collections
d=sys.argv[1]; v=len(sys.argv)>2
res=collections.Counter(); bad=[]
for f in sorted(os.listdir(d)):
    if not f.endswith('.raw') or 'Bc1' not in f: continue
    m=re.match(r'(all|bind_[0-9a-f]+_img\d)_([0-9a-f]+)_(\d+)x(\d+)',f)
    if not m: continue
    g=open(os.path.join(d,f),'rb').read()
    p=os.path.join(d,f+'.guest')
    if not os.path.exists(p): continue
    q=open(p,'rb').read()[:len(g)]
    a=collections.Counter(g[i:i+8] for i in range(0,len(g),8))
    b=collections.Counter(q[i:i+8] for i in range(0,len(q),8))
    same=sum((a&b).values())/max(1,len(g)//8)
    kind=m.group(1)[:4]
    k=(kind,'same' if same>0.999 else 'near' if same>0.9 else 'diff')
    res[k]+=1
    if same<=0.999: bad.append((f[:40],round(same,3)))
print(d,dict(res))
for b in bad[:12]: print('  ',b)
