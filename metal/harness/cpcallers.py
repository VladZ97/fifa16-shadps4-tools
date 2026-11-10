import re, sys, collections
# cpcallers.py <sample> <leaf regex> [thread]: for each sample path ending in a frame matching the regex, print the 4 nearest renderer callers
path=sys.argv[1]; pat=re.compile(sys.argv[2]); want=sys.argv[3] if len(sys.argv)>3 else 'shadPS4:GpuCommandProcessor'
lines=open(path, errors='replace').read().splitlines()
start=None
for i,l in enumerate(lines):
    if re.match(r'^    \d+ Thread_\S+: '+re.escape(want), l): start=i; break
stack=[]; out=collections.Counter()
for l in lines[start+1:]:
    if re.match(r'^    \d+ Thread_', l) or l.strip()=='': break
    m=re.match(r'^([ +|!:]*)(\d+) (.*)$', l)
    if not m: continue
    depth=len(m.group(1)); n=int(m.group(2)); name=re.sub(r'\s+\(in .*$','',m.group(3)); name=re.sub(r'\s{2,}.*$','',name)[:70]
    while stack and stack[-1][0]>=depth: stack.pop()
    stack.append((depth,name,n))
    if pat.search(name):
        # leaf-ish: count n here (children would be deeper; we accept over-count on internal matches)
        callers=[s[1] for s in stack[:-1] if re.search(r'Vulkan::|VideoCore::|AmdGpu::|Metal::|Shader::', s[1])][-4:]
        out[' <- '.join(reversed(callers))]+=n
for k,v in out.most_common(12): print(f"{v:6d}  {k}")
