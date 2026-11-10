import re,bisect,sys,collections
syms=[]
for l in open('syms_cur2.txt'):
    p=l.split(None,2)
    if len(p)==3: syms.append((int(p[0],16),p[2].strip()))
syms.sort(); keys=[s[0] for s in syms]
def name(a):
    i=bisect.bisect_right(keys,a)-1
    return re.sub(r'\(.*','',syms[i][1])[:60]
thr=None; data=collections.OrderedDict()
for l in open(sys.argv[1],encoding='latin1'):
    m=re.match(r'^\s+(\d+) Thread_(\d+)(.*)$',l)
    if m: thr=m.group(2)+m.group(3)[:40]; data[thr]=[int(m.group(1)),[]]; continue
    if l.startswith('Total number in stack'): break
    m=re.match(r'^(\s+[+!:| ]*?)(\d+) (.*)$',l)
    if not m or thr is None: continue
    d=len(m.group(1)); n=int(m.group(2)); rest=m.group(3)
    m2=re.match(r'\?\?\?  \(in shadps4\)  load address \S+ \+ (0x[0-9a-f]+)',rest)
    if m2: rest=name(0x700000000000+int(m2.group(1),16))
    else: rest=re.sub(r'\s+\[0x.*','',rest)[:60]
    data[thr][1].append((d,n,rest))
pat=sys.argv[2]; minn=int(sys.argv[3]); depth=int(sys.argv[4])
for t,(tot,fr) in data.items():
    if not re.search(pat,t): continue
    print('==',t,tot)
    base=fr[0][0] if fr else 0
    for d,n,r in fr:
        if n>=minn and d-base<=depth: print(' '*((d-base)//2),n,r)
