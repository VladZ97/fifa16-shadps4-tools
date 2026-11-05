import re
def edit(m):
    n = len(re.findall(r'fs_img[3-6]\.sample\(fs_samp[3-6], (float3\([^)]*\))\)', m))
    assert n == 4, n
    return re.sub(r'fs_img[3-6]\.sample\(fs_samp[3-6], (float3\([^)]*\))\)', r'float4(\1, 1.0)', m)
