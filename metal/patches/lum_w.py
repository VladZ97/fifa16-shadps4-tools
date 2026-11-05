import re
def edit(m):
    pat = r'float (_\d+) = 0\.693147182464599609375 \* precise::log2\(1\.9999999494757503271102905273438e-05 \+ select\((_\d+), fma\(\2, float4\(2\.0\), float4\(-1\.0\)\), bool4\(\(push_data\.depth_remap & 1u\) != 0u\)\)\.w\);'
    n = len(re.findall(pat, m)); assert n == 2, n
    return re.sub(pat, r'float \1 = \2.w;', m)
