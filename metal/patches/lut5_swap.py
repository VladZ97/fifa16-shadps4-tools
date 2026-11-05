import re
def edit(m):
    n = len(re.findall(r'fs_img[56]\.sample\(fs_samp[56], float3\(_747, _750, _749\)\)', m))
    assert n == 2, n
    return re.sub(r'(fs_img[56]\.sample\(fs_samp[56], float3\(_747, _750, _749\)\))', r'\1.zyxw', m)
