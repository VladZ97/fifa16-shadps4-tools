import re, sys, collections
# cpsample.py <sample file> [thread name]: self and inclusive counts of the thread's call tree
path=sys.argv[1]; want=sys.argv[2] if len(sys.argv)>2 else 'shadPS4:GpuCommandProcessor'
lines=open(path, errors='replace').read().splitlines()
start=None
for i,l in enumerate(lines):
    if re.match(r'^    \d+ Thread_\S+: '+re.escape(want), l): start=i; break
if start is None: print("thread not found"); sys.exit(0)
nodes=[]
for l in lines[start+1:]:
    if re.match(r'^    \d+ Thread_', l) or l.strip()=='' : break
    m=re.match(r'^([ +|!:]*)(\d+) (.*)$', l)
    if not m: continue
    depth=len(m.group(1)); count=int(m.group(2)); name=m.group(3)
    name=re.sub(r'\s+\[0x[0-9a-f]+\]','',name); name=re.sub(r'\(in [^)]*\) \+ \d+','',name)
    name=re.sub(r'std::__[a-z_]+\[abi:[^\]]+\]','',name)
    nodes.append([depth,count,name.strip()])
total=nodes[0][1] if nodes else 0
# self = count - sum of direct children
selfc=collections.Counter(); incl=collections.Counter()
for i,(d,c,n) in enumerate(nodes):
    child=0
    for j in range(i+1,len(nodes)):
        if nodes[j][0]<=d: break
        if nodes[j][0]==d+2 or nodes[j][0]==d+1 or (nodes[j][0]>d and all(nodes[k][0]>nodes[j][0] or k==j for k in range(i+1,j))):
            pass
    # simpler: direct children = following nodes with depth > d before the next node with depth <= d, keeping only minimal depth among them
    sub=[]
    for j in range(i+1,len(nodes)):
        if nodes[j][0]<=d: break
        sub.append(nodes[j])
    if sub:
        md=min(x[0] for x in sub); child=sum(x[1] for x in sub if x[0]==md)
    selfc[n[:110]]+=c-child; incl[n[:110]]+=c
print(f"thread samples: {total}")
print("--- self (busiest leaf frames):")
for n,c in selfc.most_common(22): print(f"{c:6d} {100*c/max(total,1):5.1f}%  {n}")
print("--- inclusive (renderer functions only):")
k=0
for n,c in incl.most_common(80):
    if any(s in n for s in ('Rasterizer::','Liverpool::','TextureCache::','BufferCache::','Runtime::','Scheduler::','PipelineCache::','Draw')) and 'thread_proxy' not in n:
        print(f"{c:6d} {100*c/max(total,1):5.1f}%  {n}"); k+=1
        if k>=25: break
