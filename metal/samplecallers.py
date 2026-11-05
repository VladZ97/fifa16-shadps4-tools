#!/usr/bin/env python3
"""samplecallers.py <sample file> <thread-substring> <leaf-substring> [levels]: for every node whose name
contains leaf-substring, aggregates its ancestor chain (nearest `levels` frames) by sample count."""
import sys,re,collections
f,want,leaf=sys.argv[1:4]; levels=int(sys.argv[4]) if len(sys.argv)>4 else 4
lines=open(f,errors='replace').read().split('\n')
node_re=re.compile(r'^(\s*[+!:|\s]*?)(\d+) (.*?)(?:  \(in |$)')
agg=collections.Counter(); inthread=False; stack=[]
for l in lines:
    m=re.match(r'^    (\d+) Thread_(\S+)(.*)$',l)
    if m: inthread = want in l; stack=[]; continue
    if not inthread: continue
    m=node_re.match(l)
    if not m: continue
    depth=len(m.group(1)); cnt=int(m.group(2)); name=re.sub(r'\[abi:[^\]]+\]','',m.group(3).strip()); name=re.sub(r'\(.*','',name)[:60]
    while stack and stack[-1][0]>=depth: stack.pop()
    stack.append((depth,name))
    if leaf in name:
        chain=' <- '.join(n for d,n in stack[-levels-1:-1][::-1])
        agg[chain]+=cnt
for k,v in agg.most_common(12): print(f"{v:6d}  {k}")
