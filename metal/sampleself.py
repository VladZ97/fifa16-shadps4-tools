#!/usr/bin/env python3
"""sampleself.py <sample file> [thread-substring] [top]: self time per function (count - children) from a
macOS `sample` call tree, for one thread (substring of its header) or all threads; also inclusive counts for
functions matching a few interesting names."""
import sys,re,collections
f=sys.argv[1]; want=sys.argv[2] if len(sys.argv)>2 else ''; top=int(sys.argv[3]) if len(sys.argv)>3 else 30
lines=open(f,errors='replace').read().split('\n')
# sections per thread start with "    NNNN Thread_..."
sections=[]; cur=None
for l in lines:
    m=re.match(r'^    (\d+) Thread_(\S+)(.*)$',l)
    if m:
        cur=[l,[]]; sections.append(cur); continue
    if cur is not None: cur[1].append(l)
self_c=collections.Counter(); incl=collections.Counter()
node_re=re.compile(r'^(\s*[+!:|\s]*?)(\d+) (.*?)(?:  \(in |$)')
for hdr,body in sections:
    if want and want not in hdr: continue
    stack=[]  # (depth, count, name)
    for l in body:
        m=node_re.match(l)
        if not m: continue
        depth=len(m.group(1)); cnt=int(m.group(2)); name=m.group(3).strip()
        name=re.sub(r'\[abi:[^\]]+\]','',name); name=re.sub(r'\(.*','',name)[:90]
        while stack and stack[-1][0]>=depth:
            d,c,n,child=stack.pop(); self_c[n]+=c-child
            if stack: stack[-1][3]+=c
        stack.append([depth,cnt,name,0]); incl[name]+=cnt
    while stack:
        d,c,n,child=stack.pop(); self_c[n]+=c-child
        if stack: stack[-1][3]+=c
print("self samples (top):")
for n,c in self_c.most_common(top): print(f"{c:7d}  {n}")
