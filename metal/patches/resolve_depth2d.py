import re
def edit(m):
    assert m.count("texture2d_ms<float> fs_img0 ") == 1
    m = m.replace("texture2d_ms<float> fs_img0 ", "depth2d_ms<float> fs_img0 ")
    n = len(re.findall(r'fs_img0\.read\(', m)); assert n >= 1, n
    m = re.sub(r'(float4 _\d+ = )(fs_img0\.read\([^;]*\));', r'\1float4(\2);', m)
    return m
