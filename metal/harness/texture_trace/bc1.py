# bc1.py <raw> <w> <h> <out.png> : decodes level 0 of a raw BC1 dump; prints the mean colour.
import sys, numpy as np
from PIL import Image
def decode(raw, w, h):
    bw, bh = w // 4, h // 4
    b = np.frombuffer(raw[:bw * bh * 8], dtype=np.uint8).reshape(bh, bw, 8)
    c0 = b[..., 0].astype(np.uint32) | (b[..., 1].astype(np.uint32) << 8)
    c1 = b[..., 2].astype(np.uint32) | (b[..., 3].astype(np.uint32) << 8)
    def rgb(c):
        r = (c >> 11) & 31; g = (c >> 5) & 63; bl = c & 31
        return np.stack([(r << 3) | (r >> 2), (g << 2) | (g >> 4), (bl << 3) | (bl >> 2)], -1).astype(np.float32)
    p0, p1 = rgb(c0), rgb(c1)
    four = (c0 > c1)[..., None]
    p2 = np.where(four, (2 * p0 + p1) / 3, (p0 + p1) / 2)
    p3 = np.where(four, (p0 + 2 * p1) / 3, 0)
    pal = np.stack([p0, p1, p2, p3], 2)  # bh,bw,4,3
    idx = b[..., 4:8].astype(np.uint32)
    bits = idx[..., 0] | (idx[..., 1] << 8) | (idx[..., 2] << 16) | (idx[..., 3] << 24)
    out = np.zeros((bh, 4, bw, 4, 3), np.float32)
    for y in range(4):
        for x in range(4):
            sel = (bits >> (2 * (4 * y + x))) & 3
            out[:, y, :, x, :] = np.take_along_axis(pal, sel[..., None, None].repeat(3, -1), 2)[:, :, 0, :]
    return out.reshape(h, w, 3).clip(0, 255).astype(np.uint8)
if __name__ == '__main__':
    raw = open(sys.argv[1], 'rb').read(); w, h = int(sys.argv[2]), int(sys.argv[3])
    img = decode(raw, w, h)
    m = img.reshape(-1, 3).mean(0)
    print(f"{sys.argv[1].split('/')[-1][:60]} size {len(raw)} mean rgb {m[0]:.0f} {m[1]:.0f} {m[2]:.0f} zero blocks {np.count_nonzero(np.frombuffer(raw[:w*h//2],dtype=np.uint64)==0)}")
    if len(sys.argv) > 4: Image.fromarray(img).save(sys.argv[4])
